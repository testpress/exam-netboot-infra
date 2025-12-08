#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#
#  ██████╗ ██╗  ██╗███████╗    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
#  ██╔══██╗╚██╗██╔╝██╔════╝    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
#  ██████╔╝ ╚███╔╝ █████╗      ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
#  ██╔═══╝  ██╔██╗ ██╔══╝      ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
#  ██║     ██╔╝ ██╗███████╗    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
#  ╚═╝     ╚═╝  ╚═╝╚══════╝    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
#
# ═══════════════════════════════════════════════════════════════════════════════
# PXE Server Setup Script
# Secure Exam Lab - Network Boot / Diskless Systems
# ═══════════════════════════════════════════════════════════════════════════════
#
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/testpress/exam-netboot-infra/main/pxe-server/dist/install.sh | sudo bash
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- --help
#   curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- --dry-run -v
#   curl -fsSL https://raw.githubusercontent.com/.../install.sh | sudo bash -s -- -i /path/to/ubuntu.iso -y
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

readonly VERSION="2025.12.08"
readonly BUILD_DATE="2025-12-08T08:24:34Z"

# ═══════════════════════════════════════════════════════════════════════════════
# lib/logging.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/logging.sh - Structured logging with levels, colors, and file output

# Configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-/var/log/pxe-setup.log}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"

# Get numeric value for log level
_get_log_level_num() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# Get color for log level
_get_log_color() {
    case "$1" in
        DEBUG) echo "\033[0;36m" ;;  # Cyan
        INFO)  echo "\033[0;32m" ;;  # Green
        WARN)  echo "\033[0;33m" ;;  # Yellow
        ERROR) echo "\033[0;31m" ;;  # Red
        *)     echo "" ;;
    esac
}

# Reset color
_LOG_RESET="\033[0m"

# Check if stdout is a terminal (for color support)
_use_colors() {
    [[ -t 1 ]]
}

# Core logging function
_log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Check if we should log this level
    local level_num
    level_num=$(_get_log_level_num "$level")
    local threshold
    threshold=$(_get_log_level_num "$LOG_LEVEL")
    [[ $level_num -lt $threshold ]] && return 0
    
    # Format the message
    local formatted="$ts [$level] $msg"
    
    # Output to console (with colors if terminal)
    if _use_colors; then
        local color
        color=$(_get_log_color "$level")
        if [[ "$level" == "ERROR" ]]; then
            echo -e "${color}${formatted}${_LOG_RESET}" >&2
        else
            echo -e "${color}${formatted}${_LOG_RESET}"
        fi
    else
        if [[ "$level" == "ERROR" ]]; then
            echo "$formatted" >&2
        else
            echo "$formatted"
        fi
    fi
    
    # Append to log file (without colors)
    if [[ "$LOG_TO_FILE" == true ]] && [[ -n "$LOG_FILE" ]]; then
        # Create log directory if needed
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || true
        echo "$formatted" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Convenience functions for each log level
debug() { _log DEBUG "$*"; }
info()  { _log INFO "$*"; }
warn()  { _log WARN "$*"; }
error() { _log ERROR "$*"; }

# Fatal error - log and exit
abort() {
    error "$*"
    exit 1
}

# Log a separator line
log_separator() {
    info "═══════════════════════════════════════════════════════════════"
}

# Log a step header
log_step() {
    info "▶ $*"
}

# Log success
log_success() {
    info "✓ $*"
}

# Log skip
log_skip() {
    info "⏭ $*"
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/config.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/config.sh - Configuration loading, defaults, and state management

# ═══════════════════════════════════════════════════════════════════════════════
# Default Configuration Values
# These can be overridden by config file, environment variables, or CLI args
# ═══════════════════════════════════════════════════════════════════════════════

# Required: Path to Ubuntu Desktop ISO
ISO_PATH="${ISO_PATH:-/root/ubuntu-24.04.3-desktop-amd64.iso}"

# Directories
WORK_DIR="${WORK_DIR:-/root/pxe_work}"
PXE_ROOT="${PXE_ROOT:-/srv/pxe/u2404}"
TFTP_ROOT="${TFTP_ROOT:-/tftp}"

# Config file locations
DNSMASQ_CONF="${DNSMASQ_CONF:-/etc/dnsmasq.d/pxe.conf}"
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

# Kiosk Debug/Lockdown Options (set via --kiosk-debug to disable all)
KIOSK_BLOCK_KEYS="${KIOSK_BLOCK_KEYS:-true}"           # Block F1-F12, Super key
KIOSK_DISABLE_SHORTCUTS="${KIOSK_DISABLE_SHORTCUTS:-true}"  # Disable GNOME shortcuts
KIOSK_WAIT_GNOME="${KIOSK_WAIT_GNOME:-true}"           # Wait for GNOME session
KIOSK_ENABLE_XBINDKEYS="${KIOSK_ENABLE_XBINDKEYS:-true}"  # Enable Ctrl+Alt+R reload
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
    debug "  PXE_ROOT: $PXE_ROOT"
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

# ═══════════════════════════════════════════════════════════════════════════════
# lib/preflight.sh
# ═══════════════════════════════════════════════════════════════════════════════
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
        ((errors++)) || true
    fi
    
    # Check OS (parse instead of source to avoid variable conflicts)
    if [[ -f /etc/os-release ]]; then
        local os_id os_version os_name
        os_id=$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        os_version=$(grep -oP '^VERSION_ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        os_name=$(grep -oP '^PRETTY_NAME=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        
        if [[ "$os_id" != "ubuntu" ]]; then
            warn "Script designed for Ubuntu, running on: $os_id"
            ((warnings++)) || true
        elif [[ "${os_version%%.*}" -lt 22 ]]; then
            warn "Script tested on Ubuntu 22.04+, running on: $os_version"
            ((warnings++)) || true
        else
            debug "OS check passed: $os_name"
        fi
    else
        warn "Cannot determine OS version"
        ((warnings++)) || true
    fi
    
    # Check disk space (need ~15GB for ISO extraction + squashfs work)
    local free_gb
    free_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "0")
    if [[ "$free_gb" -lt 15 ]]; then
        error "Insufficient disk space: ${free_gb}GB available, need 15GB+"
        ((errors++)) || true
    else
        debug "Disk space OK: ${free_gb}GB available"
    fi
    
    # ISO validation (warning only - iso_download step can get it)
    if [[ -n "${ISO_PATH:-}" ]] && [[ -f "$ISO_PATH" ]]; then
        if [[ ! -r "$ISO_PATH" ]]; then
            error "ISO not readable: $ISO_PATH"
            ((errors++)) || true
        else
            debug "ISO found: $ISO_PATH"
        fi
    else
        # ISO not found - iso_download step will handle it
        info "ISO not found locally - will be downloaded in iso_download step"
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
            ((warnings++)) || true
        fi
    done
    
    # Check for systemd-resolved conflict
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        warn "systemd-resolved is active - may conflict with dnsmasq on port 53"
        info "  → Consider: sudo systemctl disable --now systemd-resolved"
        ((warnings++)) || true
    fi
    
    # Check network connectivity
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        warn "No internet connectivity detected"
        warn "  Package installation may fail"
        ((warnings++)) || true
    else
        debug "Internet connectivity OK"
    fi
    
    # Check required commands that should be available in base Ubuntu
    local base_cmds=(ip hostname mount rsync)
    for cmd in "${base_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required base command not found: $cmd"
            ((errors++)) || true
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
        ((errors++)) || true
    fi
    
    if [[ -z "${SERVER_IP:-}" ]]; then
        error "SERVER_IP could not be determined"
        error "  Run detect_network_interface_and_ip first"
        ((errors++)) || true
    fi
    
    # Kiosk URL validation
    if [[ "${ENABLE_KIOSK:-true}" == true ]]; then
        if [[ -z "$KIOSK_URL" ]]; then
            error "KIOSK_URL is required when kiosk mode is enabled"
            ((errors++)) || true
        elif [[ ! "$KIOSK_URL" =~ ^https?:// ]]; then
            error "KIOSK_URL must be a valid HTTP(S) URL: $KIOSK_URL"
            ((errors++)) || true
        fi
    fi
    
    # CIDR validation for NFS networks
    for net in "${NFS_CLIENT_NETS[@]}"; do
        if [[ ! "$net" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            error "Invalid CIDR notation for NFS network: $net"
            ((errors++)) || true
        fi
    done
    
    # DHCP range validation
    if [[ ! "$DHCP_RANGE_START" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid DHCP_RANGE_START: $DHCP_RANGE_START"
        ((errors++)) || true
    fi
    
    if [[ ! "$DHCP_RANGE_END" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid DHCP_RANGE_END: $DHCP_RANGE_END"
        ((errors++)) || true
    fi
    
    if [[ $errors -gt 0 ]]; then
        abort "Configuration validation failed with $errors error(s)"
    fi
    
    log_success "Configuration validated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/network.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/network.sh - Network interface and IP detection

# ═══════════════════════════════════════════════════════════════════════════════
# Network Detection
# Auto-detect default network interface and server IP
# ═══════════════════════════════════════════════════════════════════════════════

# Global variables that will be set
DEFAULT_IF=""
SERVER_IP=""

detect_network_interface_and_ip() {
    info "Detecting network configuration..."
    
    # Allow CLI/config override via NETWORK_INTERFACE
    if [[ -n "${NETWORK_INTERFACE:-}" ]]; then
        DEFAULT_IF="$NETWORK_INTERFACE"
        info "Using specified interface: $DEFAULT_IF"
    else
        # Try to find an ethernet interface first (prefer eth*, enp*, eno* over wlan*, wlp*)
        DEFAULT_IF=""
        
        # Get all interfaces with IPv4 addresses
        local interfaces
        interfaces=$(ip -o -4 addr show | awk '{print $2}' | grep -v '^lo$' | sort -u)
        
        # Prefer ethernet over wireless
        for iface in $interfaces; do
            # Check if it's an ethernet interface (not wireless)
            if [[ "$iface" =~ ^(eth|enp|eno|ens) ]]; then
                DEFAULT_IF="$iface"
                info "Found ethernet interface: $DEFAULT_IF"
                break
            fi
        done
        
        # If no ethernet found, fall back to any interface with an IP
        if [[ -z "$DEFAULT_IF" ]]; then
            DEFAULT_IF=$(echo "$interfaces" | head -n1)
            warn "No ethernet interface found, using: $DEFAULT_IF"
        fi
    fi
    
    if [[ -z "$DEFAULT_IF" ]]; then
        abort "Cannot detect network interface. Use --interface <name> to specify manually."
    fi
    
    # Get IP address from the selected interface
    SERVER_IP=$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
    
    if [[ -z "$SERVER_IP" ]]; then
        abort "Cannot determine IP address for $DEFAULT_IF. Ensure it has an IP configured."
    fi
    
    info "Network interface: $DEFAULT_IF"
    info "Server IP: $SERVER_IP"
    
    # Export for use in other modules
    export DEFAULT_IF
    export SERVER_IP
}

# Get gateway IP (usually the router)
get_gateway_ip() {
    ip -o -4 route show to default 2>/dev/null | awk '{print $3}' | head -n1 || true
}

# Check if an IP is reachable
is_ip_reachable() {
    local ip="$1"
    local timeout="${2:-3}"
    ping -c 1 -W "$timeout" "$ip" &>/dev/null
}

# Get all IP addresses on the system
get_all_ips() {
    hostname -I 2>/dev/null || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/network_static.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/network_static.sh - Static IP configuration via netplan

# ═══════════════════════════════════════════════════════════════════════════════
# Static Network Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Configuration defaults
STATIC_IP="${STATIC_IP:-10.0.0.1/24}"
SKIP_NETWORK="${SKIP_NETWORK:-false}"

# ═══════════════════════════════════════════════════════════════════════════════
# Netplan Configuration
# ═══════════════════════════════════════════════════════════════════════════════

configure_static_ip() {
    if [[ "${SKIP_NETWORK:-false}" == true ]]; then
        info "Skipping network configuration (--skip-network)"
        return 0
    fi
    
    # Check if running on a system with netplan
    if ! command -v netplan &>/dev/null; then
        warn "netplan not found, skipping static IP configuration"
        warn "Please configure network manually"
        return 0
    fi
    
    # Ensure we have interface info
    if [[ -z "${DEFAULT_IF:-}" ]]; then
        detect_network_interface_and_ip
    fi
    
    local netplan_file="/etc/netplan/90-pxe-server.yaml"
    
    info "Configuring static IP: $STATIC_IP on $DEFAULT_IF"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would write netplan config to $netplan_file"
        info "[DRY-RUN] Interface: $DEFAULT_IF"
        info "[DRY-RUN] Static IP: $STATIC_IP"
        return 0
    fi
    
    # Backup existing netplan configs
    if [[ -d /etc/netplan ]]; then
        mkdir -p /etc/netplan/backup
        cp /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true
        debug "Backed up existing netplan configs"
    fi
    
    # Write new netplan configuration
    cat > "$netplan_file" <<EOF
# PXE Server Static IP Configuration
# Generated by pxe-server installer on $(date)
# To revert: rm $netplan_file && netplan apply

network:
  version: 2
  renderer: networkd
  
  ethernets:
    $DEFAULT_IF:
      dhcp4: false
      addresses:
        - $STATIC_IP
EOF

    # Set correct permissions
    chmod 600 "$netplan_file"
    
    log_success "Netplan configuration written: $netplan_file"
}

apply_netplan() {
    if [[ "${SKIP_NETWORK:-false}" == true ]]; then
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would run: netplan apply"
        return 0
    fi
    
    info "Applying netplan configuration..."
    
    # Generate first to check for errors
    if ! netplan generate 2>/dev/null; then
        error "Netplan configuration has errors"
        error "Check: cat /etc/netplan/90-pxe-server.yaml"
        return 1
    fi
    
    # Apply the configuration
    if netplan apply; then
        log_success "Network configuration applied"
        info "New IP: $STATIC_IP on $DEFAULT_IF"
    else
        error "Failed to apply netplan"
        error "Network may need manual configuration"
        return 1
    fi
}

# Combined function for the install step
configure_network() {
    configure_static_ip
    apply_netplan
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/iso_download.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/iso_download.sh - Auto-download Ubuntu ISO with latest version detection

# ═══════════════════════════════════════════════════════════════════════════════
# Ubuntu ISO Download Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Base URL for Ubuntu 24.04 LTS releases
UBUNTU_RELEASES_URL="${UBUNTU_RELEASES_URL:-https://releases.ubuntu.com/24.04/}"
ISO_DOWNLOAD_DIR="${ISO_DOWNLOAD_DIR:-/root}"

# ═══════════════════════════════════════════════════════════════════════════════
# Version Detection
# ═══════════════════════════════════════════════════════════════════════════════

detect_latest_iso() {
    info "Detecting latest Ubuntu 24.04.x ISO..."
    
    local iso_filename
    iso_filename=$(curl -sL "$UBUNTU_RELEASES_URL" 2>/dev/null | \
        grep -oE 'ubuntu-24\.04\.[0-9]+-desktop-amd64\.iso' | \
        sort -V | tail -1)
    
    if [[ -z "$iso_filename" ]]; then
        warn "Could not detect latest ISO version, falling back to 24.04"
        iso_filename="ubuntu-24.04-desktop-amd64.iso"
    fi
    
    echo "$iso_filename"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ISO Download
# ═══════════════════════════════════════════════════════════════════════════════

download_iso() {
    local force_download="${1:-false}"
    
    # If ISO exists and not forcing, skip
    if [[ -f "${ISO_PATH:-}" ]] && [[ "$force_download" != true ]]; then
        info "ISO already exists: $ISO_PATH"
        return 0
    fi
    
    local iso_filename
    iso_filename=$(detect_latest_iso)
    local iso_url="${UBUNTU_RELEASES_URL}${iso_filename}"
    local target_path="${ISO_DOWNLOAD_DIR}/${iso_filename}"
    
    info "Latest Ubuntu ISO: $iso_filename"
    info "Download URL: $iso_url"
    
    # Confirm download if interactive
    if [[ "${INTERACTIVE:-true}" == true ]] && [[ "${DRY_RUN:-false}" != true ]]; then
        read -rp "Download $iso_filename (~6GB)? [Y/n] " response
        case "$response" in
            [nN][oO]|[nN])
                abort "ISO download cancelled by user"
                ;;
        esac
    fi
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would download: $iso_url"
        info "[DRY-RUN] To: $target_path"
        return 0
    fi
    
    # Create download directory
    mkdir -p "$ISO_DOWNLOAD_DIR"
    
    info "Downloading Ubuntu ISO (this may take a while)..."
    
    # Try aria2c first (faster, multi-threaded)
    if command -v aria2c &>/dev/null; then
        info "Using aria2c for faster download..."
        if aria2c -x 16 -s 16 -k 1M --summary-interval=10 \
            -d "$ISO_DOWNLOAD_DIR" -o "$iso_filename" "$iso_url"; then
            ISO_PATH="$target_path"
            log_success "ISO downloaded: $ISO_PATH"
            return 0
        else
            warn "aria2c download failed, trying wget..."
        fi
    fi
    
    # Fallback to wget
    if command -v wget &>/dev/null; then
        if wget --progress=bar:force -O "$target_path" "$iso_url"; then
            ISO_PATH="$target_path"
            log_success "ISO downloaded: $ISO_PATH"
            return 0
        else
            abort "wget download failed"
        fi
    fi
    
    # Fallback to curl
    if curl -L --progress-bar -o "$target_path" "$iso_url"; then
        ISO_PATH="$target_path"
        log_success "ISO downloaded: $ISO_PATH"
        return 0
    fi
    
    abort "Failed to download ISO. Please download manually from: $iso_url"
}

# Check if ISO download is needed
check_iso_needed() {
    if [[ -z "${ISO_PATH:-}" ]] || [[ ! -f "${ISO_PATH:-}" ]]; then
        return 0  # Download needed
    fi
    return 1  # ISO exists
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/packages.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/packages.sh - Package installation

# ═══════════════════════════════════════════════════════════════════════════════
# Required Packages
# ═══════════════════════════════════════════════════════════════════════════════

readonly REQUIRED_PACKAGES=(
    dnsmasq                 # DHCP + TFTP server
    nfs-kernel-server       # NFS server for root filesystem
    unzip                   # For extracting syslinux
    squashfs-tools          # For unsquashfs/mksquashfs
    wget                    # For downloading syslinux
    xbindkeys               # For kiosk key bindings
    aria2                   # Fast multi-threaded downloader
)

# ═══════════════════════════════════════════════════════════════════════════════
# Package Installation
# ═══════════════════════════════════════════════════════════════════════════════

install_packages() {
    if [[ "${SKIP_PACKAGES:-false}" == true ]]; then
        info "Skipping package installation (--skip-packages)"
        return 0
    fi
    
    info "Installing required packages..."
    debug "Packages: ${REQUIRED_PACKAGES[*]}"
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would run: apt-get update"
        info "[DRY-RUN] Would install: ${REQUIRED_PACKAGES[*]}"
        return 0
    fi
    
    # Update package cache
    info "Updating apt cache..."
    apt-get update -y || abort "apt-get update failed"
    
    # Install packages non-interactively
    info "Installing packages (this may take a few minutes)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${REQUIRED_PACKAGES[@]}" \
        || abort "Package installation failed"
    
    log_success "All packages installed"
}

# Check if a package is installed
is_package_installed() {
    local pkg="$1"
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
}

# Check all required packages
check_required_packages() {
    local missing=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! is_package_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing[*]}"
        return 1
    fi
    
    debug "All required packages are installed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/iso.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/iso.sh - ISO mounting and webroot population

# ═══════════════════════════════════════════════════════════════════════════════
# Directory Preparation
# ═══════════════════════════════════════════════════════════════════════════════

prepare_directories() {
    info "Preparing directories..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would create directories:"
        info "  - $WORK_DIR"
        info "  - $PXE_ROOT"
        info "  - $TFTP_ROOT/bios"
        info "  - $TFTP_ROOT/boot/casper"
        info "  - $TFTP_ROOT/grub"
        return 0
    fi
    
    mkdir -p "$WORK_DIR"
    mkdir -p "$PXE_ROOT"
    mkdir -p "$TFTP_ROOT/bios"
    mkdir -p "$TFTP_ROOT/boot/casper"
    mkdir -p "$TFTP_ROOT/grub"
    mkdir -p "$TFTP_ROOT/bios/pxelinux.cfg"
    
    log_success "Directories prepared"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ISO Mounting and Content Population
# ═══════════════════════════════════════════════════════════════════════════════

mount_and_populate_pxeroot() {
    info "Mounting ISO and populating pxeroot..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would mount: $ISO_PATH"
        info "[DRY-RUN] Would rsync to: $PXE_ROOT"
        return 0
    fi
    
    # Verify ISO exists
    if [[ ! -f "$ISO_PATH" ]]; then
        abort "ISO not found: $ISO_PATH"
    fi
    
    local mnt="${WORK_DIR}/iso_mnt"
    mkdir -p "$mnt"
    
    # Mount the ISO
    info "Mounting ISO: $ISO_PATH"
    if ! mount -o loop "$ISO_PATH" "$mnt"; then
        abort "Failed to mount ISO"
    fi
    
    # Copy contents to webroot
    info "Copying ISO contents to webroot (this may take a few minutes)..."
    if ! rsync -a --delete "$mnt/" "$PXE_ROOT/"; then
        umount "$mnt" 2>/dev/null || true
        abort "Failed to copy ISO contents"
    fi
    
    # Ensure .disk directory is copied (needed for Ubuntu boot)
    if [[ -d "$mnt/.disk" ]]; then
        rsync -a "$mnt/.disk" "$PXE_ROOT/"
    fi
    
    # Unmount
    umount "$mnt"
    
    # Verify critical files exist
    if [[ ! -f "$PXE_ROOT/casper/vmlinuz" ]]; then
        abort "Kernel not found in ISO - is this a valid Ubuntu Desktop ISO?"
    fi
    
    if [[ ! -f "$PXE_ROOT/casper/initrd" ]]; then
        abort "Initrd not found in ISO - is this a valid Ubuntu Desktop ISO?"
    fi
    
    log_success "Webroot populated from ISO"
}

# Get ISO information
get_iso_info() {
    local iso="${1:-$ISO_PATH}"
    
    if [[ ! -f "$iso" ]]; then
        echo "ISO not found"
        return 1
    fi
    
    local size
    size=$(du -h "$iso" 2>/dev/null | awk '{print $1}')
    echo "ISO: $iso"
    echo "Size: $size"
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/bootloaders.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/bootloaders.sh - BIOS and UEFI bootloader setup

# ═══════════════════════════════════════════════════════════════════════════════
# Bootloader Download and Extraction
# ═══════════════════════════════════════════════════════════════════════════════

download_and_extract_bootloaders() {
    info "Downloading and extracting bootloaders..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would download syslinux from: $SYSLINUX_URL"
        info "[DRY-RUN] Would download shim-signed and grub-efi-amd64-signed"
        return 0
    fi
    
    cd "$WORK_DIR" || abort "Cannot change to work directory"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Download and extract syslinux (PXELINUX for BIOS boot)
    # ─────────────────────────────────────────────────────────────────────────
    
    if [[ ! -f "$WORK_DIR/syslinux.zip" ]]; then
        info "Downloading syslinux..."
        if ! wget -q -O syslinux.zip "$SYSLINUX_URL"; then
            abort "Failed to download syslinux from $SYSLINUX_URL"
        fi
    else
        debug "Syslinux already downloaded"
    fi
    
    info "Extracting syslinux..."
    unzip -o syslinux.zip -d "$WORK_DIR" >/dev/null || abort "Failed to extract syslinux"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Download UEFI bootloader packages
    # ─────────────────────────────────────────────────────────────────────────
    
    info "Downloading UEFI bootloader packages..."
    
    # Download .deb packages
    apt-get download shim-signed grub-efi-amd64-signed >/dev/null 2>&1 || {
        warn "Could not download UEFI packages (non-fatal)"
    }
    
    # Extract downloaded packages
    for deb in shim-signed*.deb grub-efi-amd64-signed*.deb; do
        if [[ -f "$deb" ]]; then
            local pkg_dir="${WORK_DIR}/pkg_${deb%.deb}"
            debug "Extracting $deb to $pkg_dir"
            dpkg -x "$deb" "$pkg_dir" 2>/dev/null || true
        fi
    done
    
    log_success "Bootloaders downloaded and extracted"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TFTP File Population
# ═══════════════════════════════════════════════════════════════════════════════

populate_tftp_files() {
    info "Populating TFTP directory with boot files..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would copy bootloader files to $TFTP_ROOT"
        return 0
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # BIOS boot files (pxelinux)
    # ─────────────────────────────────────────────────────────────────────────
    
    local syslinux_dir="$WORK_DIR/syslinux-6.03"
    
    if [[ -d "$syslinux_dir" ]]; then
        info "Copying BIOS boot files..."
        
        # Core pxelinux files
        cp -f "$syslinux_dir/bios/core/pxelinux.0" "$TFTP_ROOT/bios/" 2>/dev/null || \
            warn "pxelinux.0 not found"
        cp -f "$syslinux_dir/bios/core/lpxelinux.0" "$TFTP_ROOT/bios/" 2>/dev/null || \
            warn "lpxelinux.0 not found"
        
        # Required library modules
        cp -f "$syslinux_dir/bios/com32/elflink/ldlinux/ldlinux.c32" "$TFTP_ROOT/bios/" 2>/dev/null || true
        cp -f "$syslinux_dir/bios/com32/libutil/libutil.c32" "$TFTP_ROOT/bios/" 2>/dev/null || true
        cp -f "$syslinux_dir/bios/com32/lib/libcom32.c32" "$TFTP_ROOT/bios/" 2>/dev/null || true
        
        # Menu modules
        cp -f "$syslinux_dir/bios/com32/menu/menu.c32" "$TFTP_ROOT/bios/" 2>/dev/null || true
        cp -f "$syslinux_dir/bios/com32/menu/vesamenu.c32" "$TFTP_ROOT/bios/" 2>/dev/null || true
        
        debug "BIOS boot files copied"
    else
        warn "Syslinux directory not found at $syslinux_dir"
        warn "BIOS PXE boot may not work"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # UEFI boot files (grub + shim)
    # ─────────────────────────────────────────────────────────────────────────
    
    info "Copying UEFI boot files..."
    
    # Find and copy shimx64.efi
    local shim_found=false
    for d in "$WORK_DIR"/pkg_shim-signed*; do
        if [[ -d "$d" ]]; then
            local shim_file="$d/usr/lib/shim/shimx64.efi.signed"
            if [[ -f "$shim_file" ]]; then
                cp -f "$shim_file" "$TFTP_ROOT/grub/bootx64.efi"
                shim_found=true
                debug "Copied shimx64.efi"
                break
            fi
        fi
    done
    
    if [[ "$shim_found" != true ]]; then
        warn "shimx64.efi not found - UEFI boot may not work"
    fi
    
    # Find and copy grubnetx64.efi
    local grub_found=false
    for d in "$WORK_DIR"/pkg_grub-efi-amd64-signed*; do
        if [[ -d "$d" ]]; then
            local grub_file="$d/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed"
            if [[ -f "$grub_file" ]]; then
                cp -f "$grub_file" "$TFTP_ROOT/grub/grubx64.efi"
                grub_found=true
                debug "Copied grubnetx64.efi"
                break
            fi
        fi
    done
    
    if [[ "$grub_found" != true ]]; then
        warn "grubnetx64.efi not found - UEFI boot may not work"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Kernel and initrd
    # ─────────────────────────────────────────────────────────────────────────
    
    info "Copying kernel and initrd..."
    
    if [[ -f "$PXE_ROOT/casper/vmlinuz" ]] && [[ -f "$PXE_ROOT/casper/initrd" ]]; then
        cp -f "$PXE_ROOT/casper/vmlinuz" "$TFTP_ROOT/boot/casper/"
        cp -f "$PXE_ROOT/casper/initrd" "$TFTP_ROOT/boot/casper/"
        debug "Kernel and initrd copied"
    else
        abort "Kernel/initrd not found in $PXE_ROOT/casper"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Convenience symlink
    # ─────────────────────────────────────────────────────────────────────────
    
    ln -sfn /tftp/boot /tftp/bios/boot 2>/dev/null || true
    
    log_success "TFTP directory populated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/nfs.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/nfs.sh - NFS exports configuration

# ═══════════════════════════════════════════════════════════════════════════════
# NFS Configuration
# ═══════════════════════════════════════════════════════════════════════════════

configure_nfs_exports() {
    info "Configuring NFS exports..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would configure NFS exports in $NFS_EXPORTS:"
        for net in "${NFS_CLIENT_NETS[@]}"; do
            info "  $PXE_ROOT $net(ro,sync,no_subtree_check)"
        done
        return 0
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Backup existing exports file
    # ─────────────────────────────────────────────────────────────────────────
    
    if [[ -f "$NFS_EXPORTS" ]] && [[ -s "$NFS_EXPORTS" ]]; then
        local backup="${NFS_EXPORTS}.bak.$(date +%s)"
        cp -f "$NFS_EXPORTS" "$backup"
        debug "Backed up existing exports to $backup"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Add exports idempotently
    # ─────────────────────────────────────────────────────────────────────────
    
    local added=0
    for net in "${NFS_CLIENT_NETS[@]}"; do
        local entry="$PXE_ROOT $net(ro,sync,no_subtree_check)"
        
        # Check if entry already exists
        if grep -qxF "$entry" "$NFS_EXPORTS" 2>/dev/null; then
            debug "NFS export already exists: $entry"
        else
            echo "$entry" >> "$NFS_EXPORTS"
            info "Added NFS export: $PXE_ROOT for $net"
            ((added++))
        fi
    done
    
    # ─────────────────────────────────────────────────────────────────────────
    # Apply exports
    # ─────────────────────────────────────────────────────────────────────────
    
    if ! exportfs -ra; then
        abort "exportfs failed - check $NFS_EXPORTS for errors"
    fi
    
    if [[ $added -gt 0 ]]; then
        log_success "NFS exports configured ($added new entries)"
    else
        log_success "NFS exports verified (no changes needed)"
    fi
}

# Show current NFS exports
show_nfs_exports() {
    info "Current NFS exports:"
    exportfs -v 2>/dev/null || cat "$NFS_EXPORTS" 2>/dev/null || echo "No exports configured"
}

# Check if NFS is working
check_nfs_status() {
    if systemctl is-active --quiet nfs-kernel-server; then
        debug "NFS server is running"
        return 0
    else
        warn "NFS server is not running"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/dnsmasq.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/dnsmasq.sh - DHCP/TFTP configuration via dnsmasq and boot configs

# ═══════════════════════════════════════════════════════════════════════════════
# dnsmasq Configuration
# ═══════════════════════════════════════════════════════════════════════════════

write_dnsmasq_config() {
    info "Writing dnsmasq configuration..."
    
    # Ensure we have network info
    if [[ -z "${SERVER_IP:-}" ]] || [[ -z "${DEFAULT_IF:-}" ]]; then
        detect_network_interface_and_ip
    fi
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would write dnsmasq config to $DNSMASQ_CONF"
        info "[DRY-RUN] DHCP range: $DHCP_RANGE_START - $DHCP_RANGE_END"
        return 0
    fi
    
    # Write configuration
    cat > "$DNSMASQ_CONF" <<EOF
# ═══════════════════════════════════════════════════════════════════════════════
# PXE Server dnsmasq configuration
# Generated by pxe-server installer on $(date)
# ═══════════════════════════════════════════════════════════════════════════════

# Interface binding
interface=$DEFAULT_IF,lo
bind-interfaces

# Domain
domain=pxe.local

# ───────────────────────────────────────────────────────────────────────────────
# DHCP Configuration
# ───────────────────────────────────────────────────────────────────────────────
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},${DHCP_NETMASK},${DHCP_LEASE}

# Gateway (option 3) and DNS (option 6) - both point to PXE server
dhcp-option=3,$SERVER_IP
dhcp-option=6,$SERVER_IP

# No upstream DNS - clients are isolated and only access NFS
# (PXE server can use its own DNS for setup purposes)

# ───────────────────────────────────────────────────────────────────────────────
# TFTP Configuration
# ───────────────────────────────────────────────────────────────────────────────
enable-tftp
tftp-root=$TFTP_ROOT

# ───────────────────────────────────────────────────────────────────────────────
# PXE Boot Configuration
# ───────────────────────────────────────────────────────────────────────────────

# Default BIOS boot
dhcp-boot=/bios/pxelinux.0

# UEFI x86_64 detection (architecture 7 = EFI BC, 9 = EFI x86_64)
dhcp-match=set:efi64,option:client-arch,7
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:efi64,/grub/bootx64.efi

# Logging (optional - uncomment for debugging)
# log-dhcp
# log-queries
EOF
    
    # Restart dnsmasq to apply
    info "Restarting dnsmasq..."
    if ! systemctl restart dnsmasq; then
        error "Failed to restart dnsmasq"
        error "Check configuration with: dnsmasq --test"
        abort "dnsmasq restart failed"
    fi
    
    log_success "dnsmasq configured and restarted"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PXELINUX Configuration (BIOS)
# ═══════════════════════════════════════════════════════════════════════════════

write_pxelinux_cfg() {
    info "Writing PXELINUX boot menu..."
    
    if [[ -z "${SERVER_IP:-}" ]]; then
        detect_network_interface_and_ip
    fi
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would write pxelinux.cfg/default"
        return 0
    fi
    
    mkdir -p "$TFTP_ROOT/bios/pxelinux.cfg"
    
    cat > "$TFTP_ROOT/bios/pxelinux.cfg/default" <<EOF
# PXELINUX Boot Menu
# Generated by pxe-server installer

DEFAULT menu.c32
PROMPT 0
TIMEOUT 0

MENU TITLE Ubuntu PXE Boot Menu
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std

LABEL ubuntu
    MENU LABEL Ubuntu 24.04 Desktop (NFS Boot)
    MENU DEFAULT
    KERNEL /boot/casper/vmlinuz
    APPEND initrd=/boot/casper/initrd boot=casper netboot=nfs nfsroot=$SERVER_IP:$PXE_ROOT ip=dhcp quiet splash ---
EOF
    
    log_success "PXELINUX configuration written"
}

# ═══════════════════════════════════════════════════════════════════════════════
# GRUB Configuration (UEFI)
# ═══════════════════════════════════════════════════════════════════════════════

write_grub_cfg() {
    info "Writing GRUB configuration for UEFI boot..."
    
    if [[ -z "${SERVER_IP:-}" ]]; then
        detect_network_interface_and_ip
    fi
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would write grub.cfg"
        return 0
    fi
    
    cat > "$TFTP_ROOT/grub/grub.cfg" <<EOF
# GRUB Configuration for UEFI PXE Boot
# Generated by pxe-server installer

set default=0
set timeout=5

# Colors
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Ubuntu 24.04 Desktop (NFS Boot)" {
    linux /boot/casper/vmlinuz boot=casper netboot=nfs nfsroot=$SERVER_IP:$PXE_ROOT ip=dhcp quiet splash ---
    initrd /boot/casper/initrd
}

menuentry "Ubuntu 24.04 Desktop (NFS Boot - Safe Mode)" {
    linux /boot/casper/vmlinuz boot=casper netboot=nfs nfsroot=$SERVER_IP:$PXE_ROOT ip=dhcp nomodeset
    initrd /boot/casper/initrd
}
EOF
    
    log_success "GRUB configuration written"
}

# Check dnsmasq configuration
test_dnsmasq_config() {
    if dnsmasq --test 2>&1; then
        debug "dnsmasq configuration is valid"
        return 0
    else
        error "dnsmasq configuration has errors"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/kiosk.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/kiosk.sh - Kiosk mode customization (squashfs injection)

# ═══════════════════════════════════════════════════════════════════════════════
# Kiosk Customization
# Unsquash filesystem, inject autostart scripts, repack
# ═══════════════════════════════════════════════════════════════════════════════

perform_kiosk_customization() {
    # Check if kiosk is enabled
    if [[ "${ENABLE_KIOSK:-true}" != true ]]; then
        info "Kiosk customization disabled (--no-kiosk)"
        return 0
    fi
    
    info "Performing kiosk customization..."
    
    # Find squashfs file
    local squash="$PXE_ROOT/casper/filesystem.squashfs"
    
    # Try alternate name if primary not found
    if [[ ! -f "$squash" ]]; then
        squash="$PXE_ROOT/casper/minimal.squashfs"
    fi
    
    if [[ ! -f "$squash" ]]; then
        warn "squashfs not found - skipping kiosk customization"
        warn "Looked for: $PXE_ROOT/casper/filesystem.squashfs"
        warn "        and: $PXE_ROOT/casper/minimal.squashfs"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would customize squashfs: $squash"
        info "[DRY-RUN] Kiosk URL: $KIOSK_URL"
        info "[DRY-RUN] Kiosk User: $KIOSK_USER"
        return 0
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Unsquash the filesystem
    # ─────────────────────────────────────────────────────────────────────────
    
    local unsquash_dir="${WORK_DIR}/client-root"
    
    # Clean up any previous attempt
    if [[ -d "$unsquash_dir" ]]; then
        rm -rf "$unsquash_dir"
    fi
    mkdir -p "$unsquash_dir"
    
    info "Unsquashing filesystem (this may take a few minutes)..."
    if ! unsquashfs -d "$unsquash_dir" "$squash"; then
        abort "unsquashfs failed"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Inject kiosk configuration
    # ─────────────────────────────────────────────────────────────────────────
    
    _inject_kiosk_autostart "$unsquash_dir"
    _inject_kiosk_policies "$unsquash_dir"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Repack the squashfs
    # ─────────────────────────────────────────────────────────────────────────
    
    info "Repacking squashfs (this may take several minutes)..."
    
    # Backup original
    cp "$squash" "${squash}.backup" 2>/dev/null || true
    
    # Remove original and create new
    rm -f "$squash"
    if ! mksquashfs "$unsquash_dir" "$squash" -comp xz -b 1M -Xdict-size 100%; then
        # Restore backup on failure
        [[ -f "${squash}.backup" ]] && mv "${squash}.backup" "$squash"
        abort "mksquashfs failed"
    fi
    
    # Clean up
    rm -rf "$unsquash_dir"
    rm -f "${squash}.backup"
    
    log_success "Kiosk customization complete"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Kiosk Autostart Script Injection
# ═══════════════════════════════════════════════════════════════════════════════

_inject_kiosk_autostart() {
    local rootdir="$1"
    local profile_dir="$rootdir/etc/profile.d"
    mkdir -p "$profile_dir"
    
    local autostart_path="$profile_dir/99-kiosk-autostart.sh"
    info "Injecting kiosk autostart script..."
    
    # Create the autostart script with configurable options
    cat > "$autostart_path" <<KIOSK_SCRIPT
#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Kiosk Mode Autostart Script
# Generated by pxe-server installer
# ═══════════════════════════════════════════════════════════════════════════════

KIOSK_USER="${KIOSK_USER}"
KIOSK_URL="${KIOSK_URL}"
KIOSK_SSID="${KIOSK_SSID:-}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"

# Configurable lockdown options
KIOSK_BLOCK_KEYS="${KIOSK_BLOCK_KEYS:-true}"
KIOSK_DISABLE_SHORTCUTS="${KIOSK_DISABLE_SHORTCUTS:-true}"
KIOSK_WAIT_GNOME="${KIOSK_WAIT_GNOME:-true}"
KIOSK_ENABLE_XBINDKEYS="${KIOSK_ENABLE_XBINDKEYS:-true}"

LOG="/tmp/kiosk-autostart.log"
echo "\$(date -Iseconds) Kiosk script start" >> "\$LOG"

# Only run in graphical session
[ -z "\$DISPLAY" ] && exit 0

# Only run once per session
LOCKFILE="/tmp/.kiosk-started-\$USER"
[ -f "\$LOCKFILE" ] && exit 0
touch "\$LOCKFILE"

# ───────────────────────────────────────────────────────────────────────────────
# Wait for GNOME Session (configurable)
# ───────────────────────────────────────────────────────────────────────────────

wait_for_gnome() {
    if [ "\$KIOSK_WAIT_GNOME" != "true" ]; then
        sleep 3
        return
    fi
    
    echo "\$(date -Iseconds) Waiting for GNOME session..." >> "\$LOG"
    local attempts=0
    while ! gsettings list-schemas >/dev/null 2>&1; do
        sleep 1
        attempts=\$((attempts + 1))
        [ \$attempts -gt 30 ] && break
    done
    echo "\$(date -Iseconds) GNOME session ready (or timeout)" >> "\$LOG"
}

# ───────────────────────────────────────────────────────────────────────────────
# WiFi Connection (if configured)
# ───────────────────────────────────────────────────────────────────────────────

connect_wifi() {
    if [ -n "\$KIOSK_SSID" ] && [ -n "\$KIOSK_PASSWORD" ]; then
        echo "\$(date -Iseconds) Connecting to WiFi: \$KIOSK_SSID" >> "\$LOG"
        nmcli device wifi connect "\$KIOSK_SSID" password "\$KIOSK_PASSWORD" 2>/dev/null || true
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# Disable GNOME Shortcuts (configurable)
# ───────────────────────────────────────────────────────────────────────────────

disable_shortcuts() {
    if [ "\$KIOSK_DISABLE_SHORTCUTS" != "true" ]; then
        echo "\$(date -Iseconds) Skipping shortcut disable (debug mode)" >> "\$LOG"
        return
    fi
    
    echo "\$(date -Iseconds) Disabling GNOME shortcuts" >> "\$LOG"
    gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "[]" 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "[]" 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "[]" 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.keybindings close "[]" 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]" 2>/dev/null || true
    gsettings set org.gnome.mutter overlay-key '' 2>/dev/null || true
}

# ───────────────────────────────────────────────────────────────────────────────
# Block Keys (configurable) - F1-F12, Super, Ctrl+Q, etc.
# ───────────────────────────────────────────────────────────────────────────────

block_keys() {
    if [ "\$KIOSK_BLOCK_KEYS" != "true" ]; then
        echo "\$(date -Iseconds) Skipping key blocking (debug mode)" >> "\$LOG"
        return
    fi
    
    echo "\$(date -Iseconds) Blocking dangerous keys" >> "\$LOG"
    # Block F1-F12 (keycodes 67-76, 95-96), Super (133-134)
    for keycode in 67 68 69 70 71 72 73 74 75 76 95 96 133 134; do
        xmodmap -e "keycode \$keycode = NoSymbol" 2>/dev/null || true
    done
}

# ───────────────────────────────────────────────────────────────────────────────
# xbindkeys Reload Shortcut (Ctrl+Alt+R)
# ───────────────────────────────────────────────────────────────────────────────

setup_reload_shortcut() {
    if [ "\$KIOSK_ENABLE_XBINDKEYS" != "true" ]; then
        echo "\$(date -Iseconds) Skipping xbindkeys (debug mode)" >> "\$LOG"
        return
    fi
    
    local kiosk_dir="/home/\$KIOSK_USER/.kiosk"
    mkdir -p "\$kiosk_dir"
    
    # Create xbindkeys config
    cat > "\$kiosk_dir/.xbindkeysrc" <<XBIND
# Reload Firefox (Ctrl + Alt + R)
"pkill -u \$KIOSK_USER firefox; sleep 0.5; firefox --kiosk --private-window '\$KIOSK_URL' --new-instance &"
  control+alt + r
XBIND
    
    chown -R "\$KIOSK_USER:\$KIOSK_USER" "\$kiosk_dir"
    
    # Start xbindkeys
    pkill -u "\$KIOSK_USER" xbindkeys 2>/dev/null || true
    xbindkeys -f "\$kiosk_dir/.xbindkeysrc" &
    echo "\$(date -Iseconds) xbindkeys started (Ctrl+Alt+R to reload)" >> "\$LOG"
}

# ───────────────────────────────────────────────────────────────────────────────
# Prevent Screen Sleep
# ───────────────────────────────────────────────────────────────────────────────

prevent_sleep() {
    echo "\$(date -Iseconds) Disabling screen sleep" >> "\$LOG"
    xset s off 2>/dev/null || true
    xset -dpms 2>/dev/null || true
    xset s noblank 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
}

# ───────────────────────────────────────────────────────────────────────────────
# Install and Enable Firefox Systemd User Service (auto-restart)
# ───────────────────────────────────────────────────────────────────────────────

setup_firefox_service() {
    local service_dir="/home/\$KIOSK_USER/.config/systemd/user"
    mkdir -p "\$service_dir"
    
    cat > "\$service_dir/firefox-kiosk.service" <<SYSTEMD
[Unit]
Description=Firefox Kiosk Mode
After=graphical-session.target

[Service]
Type=simple
Environment=DISPLAY=:0
ExecStart=/usr/bin/firefox --kiosk --private-window \$KIOSK_URL --new-instance
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
SYSTEMD
    
    chown -R "\$KIOSK_USER:\$KIOSK_USER" "/home/\$KIOSK_USER/.config"
    
    # Enable and start the service
    sudo -u "\$KIOSK_USER" systemctl --user daemon-reload 2>/dev/null || true
    sudo -u "\$KIOSK_USER" systemctl --user enable firefox-kiosk.service 2>/dev/null || true
    sudo -u "\$KIOSK_USER" systemctl --user start firefox-kiosk.service 2>/dev/null || true
    
    echo "\$(date -Iseconds) Firefox systemd service enabled (auto-restart)" >> "\$LOG"
}

# ───────────────────────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────────────────────

wait_for_gnome
connect_wifi
disable_shortcuts
block_keys
setup_reload_shortcut
prevent_sleep
setup_firefox_service

echo "\$(date -Iseconds) Kiosk setup complete" >> "\$LOG"
KIOSK_SCRIPT

    chmod +x "$autostart_path"
    debug "Autostart script created at $autostart_path"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Firefox Policies Injection
# ═══════════════════════════════════════════════════════════════════════════════

_inject_kiosk_policies() {
    local rootdir="$1"
    local policies_dir="$rootdir/usr/lib/firefox/distribution"
    mkdir -p "$policies_dir"
    
    local policies_file="$policies_dir/policies.json"
    info "Injecting Firefox policies..."
    
    cat > "$policies_file" <<POLICIES_JSON
{
    "policies": {
        "DisableAppUpdate": true,
        "DisableFormHistory": true,
        "DisablePasswordReveal": true,
        "DisablePocket": true,
        "DisablePrivateBrowsing": false,
        "DisableProfileImport": true,
        "DisableSystemAddonUpdate": true,
        "DisableTelemetry": true,
        "DNSOverHTTPS": {
            "Enabled": false
        },
        "DontCheckDefaultBrowser": true,
        "NoDefaultBookmarks": true,
        "OfferToSaveLogins": false,
        "OverrideFirstRunPage": "",
        "PasswordManagerEnabled": false,
        "Preferences": {
            "browser.tabs.warnOnClose": false,
            "browser.shell.checkDefaultBrowser": false,
            "browser.startup.homepage_override.mstone": "ignore",
            "datareporting.policy.dataSubmissionEnabled": false
        }
    }
}
POLICIES_JSON

    chmod 644 "$policies_file"
    debug "Firefox policies created at $policies_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# lib/services.sh
# ═══════════════════════════════════════════════════════════════════════════════
# lib/services.sh - Service management and cleanup

# ═══════════════════════════════════════════════════════════════════════════════
# Service Management
# ═══════════════════════════════════════════════════════════════════════════════

restart_services() {
    info "Enabling and starting services..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would enable and start: nfs-kernel-server, dnsmasq"
        return 0
    fi
    
    local services=(nfs-kernel-server dnsmasq)
    local failed=0
    
    for service in "${services[@]}"; do
        info "Enabling $service..."
        if ! systemctl enable "$service" 2>/dev/null; then
            warn "Failed to enable $service"
            ((failed++))
        fi
        
        info "Starting $service..."
        if ! systemctl start "$service" 2>/dev/null; then
            # Try restart if start fails
            if ! systemctl restart "$service" 2>/dev/null; then
                error "Failed to start $service"
                ((failed++))
            fi
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        abort "Failed to start $failed service(s)"
    fi
    
    # Verify services are running
    info "Verifying services..."
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            debug "$service is running"
        else
            error "$service is not running"
            ((failed++))
        fi
    done
    
    if [[ $failed -gt 0 ]]; then
        abort "Service verification failed"
    fi
    
    log_success "All services running"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Cleanup Handler
# ═══════════════════════════════════════════════════════════════════════════════

cleanup_workdir() {
    local rc=$?
    
    # Don't cleanup in dry-run mode (nothing was created)
    if [[ "${DRY_RUN:-false}" == true ]]; then
        return $rc
    fi
    
    # Clean up work directory
    if [[ -d "${WORK_DIR:-}" ]]; then
        debug "Cleaning up work directory: $WORK_DIR"
        
        # Unmount any mounted filesystems
        if mountpoint -q "$WORK_DIR/iso_mnt" 2>/dev/null; then
            umount "$WORK_DIR/iso_mnt" 2>/dev/null || true
        fi
        
        # Remove work directory
        rm -rf "$WORK_DIR"
    fi
    
    return $rc
}

# ═══════════════════════════════════════════════════════════════════════════════
# Service Status Helpers
# ═══════════════════════════════════════════════════════════════════════════════

show_service_status() {
    local services=(nfs-kernel-server dnsmasq)
    
    info "Service Status:"
    for service in "${services[@]}"; do
        local status
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            status="\033[0;32mrunning\033[0m"
        else
            status="\033[0;31mstopped\033[0m"
        fi
        echo -e "  $service: $status"
    done
}

# Check all required services are running
check_all_services() {
    local services=(nfs-kernel-server dnsmasq)
    local failed=0
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            ((failed++))
        fi
    done
    
    return $failed
}

# Stop all PXE services
stop_pxe_services() {
    info "Stopping PXE services..."
    
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl stop nfs-kernel-server 2>/dev/null || true
    
    log_success "Services stopped"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════════════════════════════════
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
    iso_download
    static_ip
    packages
    directories
    pxeroot
    bootloaders
    tftp
    nfs
    pxelinux
    grub
    dnsmasq
    kiosk
    services
)

# Get step description
get_step_description() {
    case "$1" in
        iso_download) echo "Download Ubuntu ISO (if needed)" ;;
        static_ip)   echo "Configure static IP via netplan" ;;
        packages)    echo "Install required apt packages" ;;
        directories) echo "Create TFTP and PXE root directories" ;;
        pxeroot)     echo "Mount ISO and copy to PXE root" ;;
        bootloaders) echo "Download syslinux and UEFI bootloaders" ;;
        tftp)        echo "Populate TFTP with boot files" ;;
        nfs)         echo "Configure NFS exports" ;;
        pxelinux)    echo "Write PXELINUX config (BIOS)" ;;
        grub)        echo "Write GRUB config (UEFI)" ;;
        dnsmasq)     echo "Configure dnsmasq (DHCP/TFTP)" ;;
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
  --interface NAME        Network interface for PXE (default: auto-detect ethernet)
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
  --kiosk-debug           Disable kiosk lockdown (for debugging clients)

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
  iso_download - Download Ubuntu ISO (if needed)
  static_ip    - Configure static IP via netplan
  packages     - Install required apt packages
  directories  - Create TFTP and PXE root directories  
  pxeroot      - Mount ISO and copy to PXE root
  bootloaders  - Download syslinux and UEFI bootloaders
  tftp         - Populate TFTP with boot files
  nfs          - Configure NFS exports
  pxelinux     - Write PXELINUX config (BIOS)
  grub         - Write GRUB config (UEFI)
  dnsmasq      - Configure dnsmasq (DHCP/TFTP)
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
            --interface)
                if [[ -z "${2:-}" ]]; then
                    abort "Option $1 requires an interface name (e.g., eth0, enp3s0)"
                fi
                NETWORK_INTERFACE="$2"
                shift 2
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
            --kiosk-debug)
                # Disable all kiosk lockdown for debugging
                KIOSK_BLOCK_KEYS=false
                KIOSK_DISABLE_SHORTCUTS=false
                KIOSK_WAIT_GNOME=false
                KIOSK_ENABLE_XBINDKEYS=false
                info "Kiosk debug mode: all lockdown options disabled"
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
        iso_download) echo "download_iso" ;;
        static_ip)   echo "configure_network" ;;
        packages)    echo "install_packages" ;;
        directories) echo "prepare_directories" ;;
        pxeroot)     echo "mount_and_populate_pxeroot" ;;
        bootloaders) echo "download_and_extract_bootloaders" ;;
        tftp)        echo "populate_tftp_files" ;;
        nfs)         echo "configure_nfs_exports" ;;
        pxelinux)    echo "write_pxelinux_cfg" ;;
        grub)        echo "write_grub_cfg" ;;
        dnsmasq)     echo "write_dnsmasq_config" ;;
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
    info "    • HTTP Root:    $PXE_ROOT"
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
