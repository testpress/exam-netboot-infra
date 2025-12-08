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

# Detect if running via pipe (curl | bash)
if [[ ! -t 0 ]]; then
    INTERACTIVE=false
fi

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

EXAMPLES:
  # First-time interactive setup
  sudo ./install.sh --iso /root/ubuntu-24.04.3-desktop-amd64.iso

  # Non-interactive setup via curl
  curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- -i /root/ubuntu.iso -y

  # Dry-run to preview changes
  sudo ./install.sh --dry-run --verbose

  # Re-run with existing config
  sudo ./install.sh -c /etc/pxe-server/config.conf

  # Force re-run all steps
  sudo ./install.sh --force

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
    # Execute installation steps
    # ─────────────────────────────────────────────────────────────────────────
    
    log_separator
    info "Starting PXE server installation..."
    log_separator
    
    run_step "packages"       install_packages
    run_step "directories"    prepare_directories
    run_step "webroot"        mount_and_populate_webroot
    run_step "bootloaders"    download_and_extract_bootloaders
    run_step "tftp"           populate_tftp_files
    run_step "nfs"            configure_nfs_exports
    run_step "pxelinux"       write_pxelinux_cfg
    run_step "grub"           write_grub_cfg
    run_step "dnsmasq"        write_dnsmasq_config
    run_step "nginx"          configure_nginx_site
    run_step "kiosk"          perform_kiosk_customization
    run_step "services"       restart_services
    
    # ─────────────────────────────────────────────────────────────────────────
    # Show summary
    # ─────────────────────────────────────────────────────────────────────────
    
    show_summary
}

# Run main function with all arguments
main "$@"
