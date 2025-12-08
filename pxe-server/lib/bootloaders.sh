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
    
    if [[ -f "$PXE_WEBROOT/casper/vmlinuz" ]] && [[ -f "$PXE_WEBROOT/casper/initrd" ]]; then
        cp -f "$PXE_WEBROOT/casper/vmlinuz" "$TFTP_ROOT/boot/casper/"
        cp -f "$PXE_WEBROOT/casper/initrd" "$TFTP_ROOT/boot/casper/"
        debug "Kernel and initrd copied"
    else
        abort "Kernel/initrd not found in $PXE_WEBROOT/casper"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # Convenience symlink
    # ─────────────────────────────────────────────────────────────────────────
    
    ln -sfn /tftp/boot /tftp/bios/boot 2>/dev/null || true
    
    log_success "TFTP directory populated"
}
