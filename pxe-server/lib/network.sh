#!/usr/bin/env bash
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
