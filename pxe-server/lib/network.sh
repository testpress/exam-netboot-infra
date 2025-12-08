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
    
    # Find the default route interface
    DEFAULT_IF="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1 || true)"
    
    if [[ -z "$DEFAULT_IF" ]]; then
        abort "Cannot detect default network interface"
    fi
    
    # Get the primary IP address
    SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    
    if [[ -z "$SERVER_IP" ]]; then
        # Fallback: try to get IP from the detected interface
        SERVER_IP="$(ip -4 addr show "$DEFAULT_IF" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)"
    fi
    
    if [[ -z "$SERVER_IP" ]]; then
        abort "Cannot determine server IP address"
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
