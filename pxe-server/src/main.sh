#!/usr/bin/env bash
# src/main.sh - CLI parsing and main orchestration
# This file is bundled into the final install.sh by build.sh

# ═══════════════════════════════════════════════════════════════════════════════
# CLI Defaults
# ═══════════════════════════════════════════════════════════════════════════════

DRY_RUN=false
VERBOSE=false
SKIP_PACKAGES=false
FORCE_REINSTALL=false
INTERACTIVE=true
RUN_SINGLE_STEP=""
FROM_STEP=""

# Detect if running via pipe (curl | bash)
if [[ ! -t 0 ]]; then
    INTERACTIVE=false
fi

# All available steps in order
ALL_STEPS=(
    packages
    directories
    webroot
    bootloaders
    tftp
    nfs
    pxelinux
    grub
    dnsmasq
    nginx
    kiosk
    services
)

# Get step description
get_step_description() {
    case "$1" in
        packages)    echo "Install required apt packages" ;;
        directories) echo "Create TFTP and webroot directories" ;;
        webroot)     echo "Mount ISO and copy to webroot" ;;
        bootloaders) echo "Download syslinux and UEFI bootloaders" ;;
        tftp)        echo "Populate TFTP with boot files" ;;
        nfs)         echo "Configure NFS exports" ;;
        pxelinux)    echo "Write PXELINUX config (BIOS)" ;;
        grub)        echo "Write GRUB config (UEFI)" ;;
        dnsmasq)     echo "Configure dnsmasq (DHCP/TFTP)" ;;
        nginx)       echo "Configure nginx web server" ;;
        kiosk)       echo "Customize squashfs for kiosk mode" ;;
        services)    echo "Enable and start services" ;;
        *)           echo "" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Banner and Help
# ═══════════════════════════════════════════════════════════════════════════════

show_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          PXE Server Setup for Secure Exam Lab                 ║"
    echo "║          Ubuntu 24.04 Desktop - Network Boot                  ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Version: ${VERSION:-dev}"
    echo "  Build:   ${BUILD_DATE:-local}"
    echo ""
}

show_help() {
    cat <<'HELP_EOF'
Usage: install.sh [OPTIONS]

PXE Server Setup for Ubuntu Exam Kiosk Environment

OPTIONS:
  -c, --config FILE       Config file path (default: /etc/pxe-server/config.conf)
  -i, --iso PATH          Path to Ubuntu Desktop ISO (required first time)
  --no-kiosk              Disable kiosk customization
  --dry-run               Show what would be done without executing
  --skip-packages         Skip apt package installation
  --force                 Force re-run of completed steps
  -v, --verbose           Enable debug output
  -y, --yes               Non-interactive mode (assume yes to prompts)
  -h, --help              Show this help message
  --version               Show version information

STEP CONTROL:
  --list-steps            List all steps and their completion status
  --step <name>           Run only a single step (useful for debugging)
  --from-step <name>      Resume from a specific step (skip earlier steps)
  --reset                 Clear all progress and start fresh

EXAMPLES:
  # First-time interactive setup
  sudo ./install.sh --iso /root/ubuntu-24.04.3-desktop-amd64.iso

  # Non-interactive setup via curl
  curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- -i /root/ubuntu.iso -y

  # Dry-run to preview changes
  sudo ./install.sh --dry-run --verbose

  # Check which steps are complete
  sudo ./install.sh --list-steps

  # Run only the kiosk step
  sudo ./install.sh --step kiosk

  # Resume from dnsmasq step (skip packages, directories, etc.)
  sudo ./install.sh --from-step dnsmasq

  # Force re-run all steps
  sudo ./install.sh --force

  # Reset all progress and start fresh
  sudo ./install.sh --reset

AVAILABLE STEPS:
  packages     - Install required apt packages
  directories  - Create TFTP and webroot directories  
  webroot      - Mount ISO and copy to webroot
  bootloaders  - Download syslinux and UEFI bootloaders
  tftp         - Populate TFTP with boot files
  nfs          - Configure NFS exports
  pxelinux     - Write PXELINUX config (BIOS)
  grub         - Write GRUB config (UEFI)
  dnsmasq      - Configure dnsmasq (DHCP/TFTP)
  nginx        - Configure nginx web server
  kiosk        - Customize squashfs for kiosk mode
  services     - Enable and start services

ENVIRONMENT VARIABLES:
  ISO_PATH                Path to Ubuntu ISO
  CONFIG_FILE             Config file path
  SECRETS_FILE            Secrets file for WiFi credentials
  LOG_LEVEL               DEBUG, INFO, WARN, ERROR (default: INFO)
  LOG_FILE                Log file path (default: /var/log/pxe-setup.log)

CONFIGURATION:
  Create /etc/pxe-server/config.conf with your settings.
  See documentation for all available options.

HELP_EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step Listing
# ═══════════════════════════════════════════════════════════════════════════════

list_steps() {
    load_config 2>/dev/null || true
    init_state 2>/dev/null || true
    
    echo ""
    echo "Installation Steps:"
    echo "─────────────────────────────────────────────────────────────────"
    printf "  %-3s %-15s %s\n" "#" "STEP" "STATUS"
    echo "─────────────────────────────────────────────────────────────────"
    
    local i=1
    for step in "${ALL_STEPS[@]}"; do
        local status
        local desc
        desc=$(get_step_description "$step")
        
        if is_step_complete "$step" 2>/dev/null; then
            status="✅ complete"
        else
            status="⬚ pending"
        fi
        
        printf "  %-3d %-15s %-12s  %s\n" "$i" "$step" "$status" "$desc"
        ((i++))
    done
    
    echo "─────────────────────────────────────────────────────────────────"
    echo ""
    echo "State file: ${STATE_FILE:-/var/lib/pxe-setup/completed_steps}"
    echo ""
    echo "Usage:"
    echo "  --step <name>       Run single step"
    echo "  --from-step <name>  Resume from step"
    echo "  --force             Re-run completed steps"
    echo "  --reset             Clear all progress"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Argument Parsing
# ═══════════════════════════════════════════════════════════════════════════════

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                if [[ -z "${2:-}" ]]; then
                    abort "Option $1 requires an argument"
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            -i|--iso)
                if [[ -z "${2:-}" ]]; then
                    abort "Option $1 requires an argument"
                fi
                ISO_PATH="$2"
                shift 2
                ;;
            --no-kiosk)
                ENABLE_KIOSK=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-packages)
                SKIP_PACKAGES=true
                shift
                ;;
            --force)
                FORCE_REINSTALL=true
                shift
                ;;
            --list-steps)
                list_steps
                exit 0
                ;;
            --step)
                if [[ -z "${2:-}" ]]; then
                    abort "Option $1 requires a step name"
                fi
                RUN_SINGLE_STEP="$2"
                shift 2
                ;;
            --from-step)
                if [[ -z "${2:-}" ]]; then
                    abort "Option $1 requires a step name"
                fi
                FROM_STEP="$2"
                shift 2
                ;;
            --reset)
                load_config 2>/dev/null || true
                reset_state
                echo "Progress reset. Run again to start fresh."
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                LOG_LEVEL=DEBUG
                shift
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                echo "pxe-server v${VERSION:-dev}"
                echo "Build: ${BUILD_DATE:-local}"
                exit 0
                ;;
            --)
                # End of options
                shift
                break
                ;;
            -*)
                abort "Unknown option: $1. Use --help for usage."
                ;;
            *)
                # Positional argument - could be ISO path
                if [[ -z "${ISO_PATH:-}" ]] && [[ -f "$1" ]]; then
                    ISO_PATH="$1"
                fi
                shift
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step Validation
# ═══════════════════════════════════════════════════════════════════════════════

validate_step_name() {
    local step="$1"
    for s in "${ALL_STEPS[@]}"; do
        if [[ "$s" == "$step" ]]; then
            return 0
        fi
    done
    abort "Unknown step: $step. Use --list-steps to see available steps."
}

get_step_function() {
    local step="$1"
    case "$step" in
        packages)    echo "install_packages" ;;
        directories) echo "prepare_directories" ;;
        webroot)     echo "mount_and_populate_webroot" ;;
        bootloaders) echo "download_and_extract_bootloaders" ;;
        tftp)        echo "populate_tftp_files" ;;
        nfs)         echo "configure_nfs_exports" ;;
        pxelinux)    echo "write_pxelinux_cfg" ;;
        grub)        echo "write_grub_cfg" ;;
        dnsmasq)     echo "write_dnsmasq_config" ;;
        nginx)       echo "configure_nginx_site" ;;
        kiosk)       echo "perform_kiosk_customization" ;;
        services)    echo "restart_services" ;;
        *) abort "Unknown step: $step" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Confirmation Prompt
# ═══════════════════════════════════════════════════════════════════════════════

confirm_proceed() {
    # Skip in non-interactive or dry-run mode
    if [[ "$INTERACTIVE" != true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo ""
    echo "This script will:"
    echo "  • Install packages: nginx, dnsmasq, nfs-kernel-server, etc."
    echo "  • Configure DHCP/TFTP server on this machine"
    echo "  • Set up NFS exports for PXE root filesystem"
    echo "  • Configure nginx for ISO content serving"
    if [[ "${ENABLE_KIOSK:-true}" == true ]]; then
        echo "  • Customize squashfs for kiosk mode"
    fi
    echo ""
    echo "Server IP: ${SERVER_IP:-detecting...}"
    echo "ISO Path:  ${ISO_PATH:-not specified}"
    echo ""
    
    read -rp "Continue? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            echo "Aborted by user."
            exit 0
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Summary Display
# ═══════════════════════════════════════════════════════════════════════════════

show_summary() {
    log_separator
    info ""
    info "  ✅ PXE Server Setup Complete!"
    info ""
    log_separator
    info ""
    info "  Server Configuration:"
    info "    • IP Address:   $SERVER_IP"
    info "    • TFTP Root:    $TFTP_ROOT"
    info "    • HTTP Root:    $PXE_WEBROOT"
    info "    • DHCP Range:   $DHCP_RANGE_START - $DHCP_RANGE_END"
    info ""
    info "  Client Networks:  ${NFS_CLIENT_NETS[*]}"
    info ""
    if [[ "${ENABLE_KIOSK:-true}" == true ]]; then
        info "  Kiosk Mode:       Enabled"
        info "    • URL:          $KIOSK_URL"
        info "    • User:         $KIOSK_USER"
    else
        info "  Kiosk Mode:       Disabled"
    fi
    info ""
    info "  Next Steps:"
    info "    1. Configure client machines to PXE boot (BIOS/UEFI)"
    info "    2. Ensure clients are on network: ${NFS_CLIENT_NETS[*]}"
    info "    3. Boot a client to test"
    info ""
    info "  Troubleshooting:"
    info "    sudo journalctl -u dnsmasq -n 50"
    info "    sudo journalctl -u nginx -n 50"
    info "    sudo journalctl -u nfs-kernel-server -n 50"
    info "    tail -f ${LOG_FILE:-/var/log/pxe-setup.log}"
    info ""
    log_separator
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    # Parse command-line arguments
    parse_args "$@"
    
    # Show banner
    show_banner
    
    # Load configuration
    load_config
    
    # Detect network
    detect_network_interface_and_ip
    
    # Run preflight checks
    preflight_checks
    
    # Validate configuration
    validate_config
    
    # Confirm with user (if interactive)
    confirm_proceed
    
    # Initialize state tracking
    init_state
    
    # Set up cleanup handler
    trap cleanup_workdir EXIT
    
    # ─────────────────────────────────────────────────────────────────────────
    # Single step mode
    # ─────────────────────────────────────────────────────────────────────────
    
    if [[ -n "$RUN_SINGLE_STEP" ]]; then
        validate_step_name "$RUN_SINGLE_STEP"
        local func
        func=$(get_step_function "$RUN_SINGLE_STEP")
        
        log_separator
        info "Running single step: $RUN_SINGLE_STEP"
        log_separator
        
        run_step "$RUN_SINGLE_STEP" "$func"
        
        log_success "Step '$RUN_SINGLE_STEP' completed!"
        info "Use --list-steps to see overall progress."
        return 0
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Execute installation steps
    # ─────────────────────────────────────────────────────────────────────────
    
    log_separator
    info "Starting PXE server installation..."
    log_separator
    
    local skip_until_found=false
    if [[ -n "$FROM_STEP" ]]; then
        validate_step_name "$FROM_STEP"
        skip_until_found=true
        info "Resuming from step: $FROM_STEP"
    fi
    
    for step in "${ALL_STEPS[@]}"; do
        # Handle --from-step
        if [[ "$skip_until_found" == true ]]; then
            if [[ "$step" == "$FROM_STEP" ]]; then
                skip_until_found=false
            else
                log_skip "Skipping $step (before --from-step)"
                continue
            fi
        fi
        
        local func
        func=$(get_step_function "$step")
        run_step "$step" "$func"
    done
    
    # ─────────────────────────────────────────────────────────────────────────
    # Show summary
    # ─────────────────────────────────────────────────────────────────────────
    
    show_summary
}

# Run main function with all arguments
main "$@"
