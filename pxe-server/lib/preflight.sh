#!/usr/bin/env bash
# lib/preflight.sh - Pre-execution validation and checks

# ═══════════════════════════════════════════════════════════════════════════════
# Preflight Checks
# Run before making any changes to validate environment
# ═══════════════════════════════════════════════════════════════════════════════

preflight_checks() {
    info "Running preflight checks..."
    local errors=0
    local warnings=0
    
    # ─────────────────────────────────────────────────────────────────────────
    # Critical checks (will abort if failed)
    # ─────────────────────────────────────────────────────────────────────────
    
    # Check running as root
    if [[ $(id -u) -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        ((errors++))
    fi
    
    # Check OS (parse instead of source to avoid variable conflicts)
    if [[ -f /etc/os-release ]]; then
        local os_id os_version os_name
        os_id=$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        os_version=$(grep -oP '^VERSION_ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        os_name=$(grep -oP '^PRETTY_NAME=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        
        if [[ "$os_id" != "ubuntu" ]]; then
            warn "Script designed for Ubuntu, running on: $os_id"
            ((warnings++))
        elif [[ "${os_version%%.*}" -lt 22 ]]; then
            warn "Script tested on Ubuntu 22.04+, running on: $os_version"
            ((warnings++))
        else
            debug "OS check passed: $os_name"
        fi
    else
        warn "Cannot determine OS version"
        ((warnings++))
    fi
    
    # Check disk space (need ~15GB for ISO extraction + squashfs work)
    local free_gb
    free_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "0")
    if [[ "$free_gb" -lt 15 ]]; then
        error "Insufficient disk space: ${free_gb}GB available, need 15GB+"
        ((errors++))
    else
        debug "Disk space OK: ${free_gb}GB available"
    fi
    
    # ISO validation
    if [[ ! -f "$ISO_PATH" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            warn "ISO not found: $ISO_PATH (continuing in dry-run mode)"
            ((warnings++))
        else
            error "ISO not found: $ISO_PATH"
            error "  Download from: https://ubuntu.com/download/desktop"
            ((errors++))
        fi
    elif [[ ! -r "$ISO_PATH" ]]; then
        error "ISO not readable: $ISO_PATH"
        ((errors++))
    else
        debug "ISO found: $ISO_PATH"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Warning checks (will continue but notify)
    # ─────────────────────────────────────────────────────────────────────────
    
    # Check for port conflicts
    for port in 67 69 80; do
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            local service
            service=$(ss -tlnp 2>/dev/null | grep ":$port " | awk '{print $NF}' | head -1)
            warn "Port $port already in use by: $service"
            ((warnings++))
        fi
    done
    
    # Check for systemd-resolved conflict
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        warn "systemd-resolved is active - may conflict with dnsmasq on port 53"
        info "  → Consider: sudo systemctl disable --now systemd-resolved"
        ((warnings++))
    fi
    
    # Check network connectivity
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        warn "No internet connectivity detected"
        warn "  Package installation may fail"
        ((warnings++))
    else
        debug "Internet connectivity OK"
    fi
    
    # Check required commands that should be available in base Ubuntu
    local base_cmds=(ip hostname mount rsync)
    for cmd in "${base_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required base command not found: $cmd"
            ((errors++))
        fi
    done
    
    # ─────────────────────────────────────────────────────────────────────────
    # Summary
    # ─────────────────────────────────────────────────────────────────────────
    
    if [[ $errors -gt 0 ]]; then
        abort "Preflight failed with $errors error(s) and $warnings warning(s)"
    fi
    
    if [[ $warnings -gt 0 ]]; then
        info "Preflight completed with $warnings warning(s)"
    else
        log_success "Preflight checks passed"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration Validation
# Validate configuration values after loading
# ═══════════════════════════════════════════════════════════════════════════════

validate_config() {
    info "Validating configuration..."
    local errors=0
    
    # Required values
    if [[ -z "$ISO_PATH" ]]; then
        error "ISO_PATH is required"
        ((errors++))
    fi
    
    if [[ -z "${SERVER_IP:-}" ]]; then
        error "SERVER_IP could not be determined"
        error "  Run detect_network_interface_and_ip first"
        ((errors++))
    fi
    
    # Kiosk URL validation
    if [[ "${ENABLE_KIOSK:-true}" == true ]]; then
        if [[ -z "$KIOSK_URL" ]]; then
            error "KIOSK_URL is required when kiosk mode is enabled"
            ((errors++))
        elif [[ ! "$KIOSK_URL" =~ ^https?:// ]]; then
            error "KIOSK_URL must be a valid HTTP(S) URL: $KIOSK_URL"
            ((errors++))
        fi
    fi
    
    # CIDR validation for NFS networks
    for net in "${NFS_CLIENT_NETS[@]}"; do
        if [[ ! "$net" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            error "Invalid CIDR notation for NFS network: $net"
            ((errors++))
        fi
    done
    
    # DHCP range validation
    if [[ ! "$DHCP_RANGE_START" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid DHCP_RANGE_START: $DHCP_RANGE_START"
        ((errors++))
    fi
    
    if [[ ! "$DHCP_RANGE_END" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid DHCP_RANGE_END: $DHCP_RANGE_END"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        abort "Configuration validation failed with $errors error(s)"
    fi
    
    log_success "Configuration validated"
}
