#!/usr/bin/env bash
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
