#!/usr/bin/env bash
# lib/packages.sh - Package installation

# ═══════════════════════════════════════════════════════════════════════════════
# Required Packages
# ═══════════════════════════════════════════════════════════════════════════════

readonly REQUIRED_PACKAGES=(
    nginx                   # Web server for serving ISO contents
    dnsmasq                 # DHCP + TFTP server
    nfs-kernel-server       # NFS server for root filesystem
    unzip                   # For extracting syslinux
    squashfs-tools          # For unsquashfs/mksquashfs
    wget                    # For downloading syslinux
    xbindkeys               # For kiosk key bindings
    iptables                # For firewall rules in kiosk
    aria2                   # Fast downloader (optional)
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
