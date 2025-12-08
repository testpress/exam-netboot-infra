#!/usr/bin/env bash
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
    
    # ─────────────────────────────────────────────────────────────────────────
    # BIOS boot files (pxelinux)
    # ─────────────────────────────────────────────────────────────────────────
    
    # Check for extracted syslinux directory (handle version variances)
    local syslinux_dir
    syslinux_dir=$(find "$WORK_DIR" -maxdepth 1 -type d -name "syslinux-*" | head -n 1)
    
    if [[ -d "$syslinux_dir" ]]; then
        info "Copying BIOS boot files from $syslinux_dir..."
        
        # Core pxelinux files (search recursively as layout can vary)
        find "$syslinux_dir" -name "pxelinux.0" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        find "$syslinux_dir" -name "lpxelinux.0" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        
        # Required library modules
        find "$syslinux_dir" -name "ldlinux.c32" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        find "$syslinux_dir" -name "libutil.c32" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        find "$syslinux_dir" -name "libcom32.c32" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        
        # Menu modules
        find "$syslinux_dir" -name "menu.c32" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        find "$syslinux_dir" -name "vesamenu.c32" -exec cp -f {} "$TFTP_ROOT/bios/" \;
        
        debug "BIOS boot files copied"
    else
        warn "Syslinux directory not found in $WORK_DIR. Contents:"
        ls -la "$WORK_DIR" | head -n 5
        warn "BIOS PXE boot may not work"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # UEFI boot files (grub + shim)
    # ─────────────────────────────────────────────────────────────────────────
    
    info "Copying UEFI boot files..."
    
    # Find and copy shimx64.efi (handle different paths/versions)
    local shim_file
    shim_file=$(find "$WORK_DIR" -name "shimx64.efi.signed" -o -name "shimx64.efi" | head -n 1)
    
    if [[ -f "$shim_file" ]]; then
        cp -f "$shim_file" "$TFTP_ROOT/grub/bootx64.efi"
        debug "Copied shim: $shim_file -> bootx64.efi"
    else
        warn "shimx64.efi not found in downloaded packages"
        warn "UEFI Secure Boot may not work"
    fi
    
    # Find and copy grubnetx64.efi
    local grub_file
    grub_file=$(find "$WORK_DIR" -name "grubnetx64.efi.signed" -o -name "grubnetx64.efi" | head -n 1)
    
    if [[ -f "$grub_file" ]]; then
        cp -f "$grub_file" "$TFTP_ROOT/grub/grubx64.efi"
        debug "Copied grub: $grub_file -> grubx64.efi"
    else
        warn "grubnetx64.efi not found in downloaded packages"
        warn "UEFI boot may not work"
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
