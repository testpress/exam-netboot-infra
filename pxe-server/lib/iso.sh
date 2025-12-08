#!/usr/bin/env bash
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
