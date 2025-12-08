#!/usr/bin/env bash
# lib/config.sh - Configuration loading, defaults, and state management

# ═══════════════════════════════════════════════════════════════════════════════
# Default Configuration Values
# These can be overridden by config file, environment variables, or CLI args
# ═══════════════════════════════════════════════════════════════════════════════

# Required: Path to Ubuntu Desktop ISO
ISO_PATH="${ISO_PATH:-/root/ubuntu-24.04.3-desktop-amd64.iso}"

# Directories
WORK_DIR="${WORK_DIR:-/root/pxe_work}"
PXE_WEBROOT="${PXE_WEBROOT:-/var/www/html/desktop/u2404}"
TFTP_ROOT="${TFTP_ROOT:-/tftp}"

# Config file locations
DNSMASQ_CONF="${DNSMASQ_CONF:-/etc/dnsmasq.d/pxe.conf}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-enabled/pxe.conf}"
NFS_EXPORTS="${NFS_EXPORTS:-/etc/exports}"

# DHCP Settings
DHCP_RANGE_START="${DHCP_RANGE_START:-10.0.0.170}"
DHCP_RANGE_END="${DHCP_RANGE_END:-10.0.0.200}"
DHCP_NETMASK="${DHCP_NETMASK:-255.255.255.0}"
DHCP_LEASE="${DHCP_LEASE:-12h}"

# NFS Client Networks (will be converted to array)
NFS_CLIENT_NETS_STR="${NFS_CLIENT_NETS:-10.0.0.0/24 192.168.1.0/24}"
NFS_CLIENT_NETS=()

# Kiosk Settings
ENABLE_KIOSK="${ENABLE_KIOSK:-true}"
KIOSK_USER="${KIOSK_USER:-ubuntu}"
KIOSK_URL="${KIOSK_URL:-https://lmsdemo.testpress.in}"
KIOSK_SSID="${KIOSK_SSID:-}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"

# Syslinux/PXELINUX download URL
SYSLINUX_URL="${SYSLINUX_URL:-https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.zip}"

# State tracking directory
STATE_DIR="${STATE_DIR:-/var/lib/pxe-setup}"
STATE_FILE=""

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration Loading
# ═══════════════════════════════════════════════════════════════════════════════

load_config() {
    local config_file="${CONFIG_FILE:-/etc/pxe-server/config.conf}"
    
    # Load main config file if exists
    if [[ -f "$config_file" ]]; then
        info "Loading configuration from $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        debug "No config file at $config_file, using defaults"
    fi
    
    # Load secrets file separately (for WiFi credentials, etc.)
    local secrets_file="${SECRETS_FILE:-/etc/pxe-server/secrets.conf}"
    if [[ -f "$secrets_file" ]]; then
        debug "Loading secrets from $secrets_file"
        # shellcheck source=/dev/null
        source "$secrets_file"
    fi
    
    # Parse NFS_CLIENT_NETS into array
    if [[ ${#NFS_CLIENT_NETS[@]} -eq 0 ]] || [[ "${NFS_CLIENT_NETS[*]}" == "" ]]; then
        read -ra NFS_CLIENT_NETS <<< "$NFS_CLIENT_NETS_STR"
    fi
    
    # Set state file path
    STATE_FILE="$STATE_DIR/completed_steps"
    
    debug "Configuration loaded:"
    debug "  ISO_PATH: $ISO_PATH"
    debug "  PXE_WEBROOT: $PXE_WEBROOT"
    debug "  TFTP_ROOT: $TFTP_ROOT"
    debug "  ENABLE_KIOSK: $ENABLE_KIOSK"
    debug "  NFS_CLIENT_NETS: ${NFS_CLIENT_NETS[*]}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# State Management (for idempotency)
# ═══════════════════════════════════════════════════════════════════════════════

init_state() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        debug "[DRY-RUN] Would initialize state directory: $STATE_DIR"
        return 0
    fi
    
    mkdir -p "$STATE_DIR"
    touch "$STATE_FILE"
    debug "State initialized at $STATE_DIR"
}

mark_step_complete() {
    local step="$1"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        debug "[DRY-RUN] Would mark step complete: $step"
        return 0
    fi
    
    if ! grep -qxF "$step" "$STATE_FILE" 2>/dev/null; then
        echo "$step" >> "$STATE_FILE"
    fi
    log_success "Step completed: $step"
}

is_step_complete() {
    local step="$1"
    
    # In dry-run mode, always return false so we show what would happen
    if [[ "${DRY_RUN:-false}" == true ]]; then
        return 1
    fi
    
    grep -qxF "$step" "$STATE_FILE" 2>/dev/null
}

reset_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        info "State reset - all steps will run again"
    fi
}

# Run a step with idempotency check
run_step() {
    local step_name="$1"
    local step_func="$2"
    
    if is_step_complete "$step_name" && [[ "${FORCE_REINSTALL:-false}" != true ]]; then
        log_skip "Skipping $step_name (already complete, use --force to rerun)"
        return 0
    fi
    
    log_step "Running: $step_name"
    "$step_func"
    mark_step_complete "$step_name"
}
