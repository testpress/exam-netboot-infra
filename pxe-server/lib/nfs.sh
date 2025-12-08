#!/usr/bin/env bash
# lib/nfs.sh - NFS exports configuration

# ═══════════════════════════════════════════════════════════════════════════════
# NFS Configuration
# ═══════════════════════════════════════════════════════════════════════════════

configure_nfs_exports() {
    info "Configuring NFS exports..."
    
    if [[ "${DRY_RUN:-false}" == true ]]; then
        info "[DRY-RUN] Would configure NFS exports in $NFS_EXPORTS:"
        for net in "${NFS_CLIENT_NETS[@]}"; do
            info "  $PXE_WEBROOT $net(ro,sync,no_subtree_check)"
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
        local entry="$PXE_WEBROOT $net(ro,sync,no_subtree_check)"
        
        # Check if entry already exists
        if grep -qxF "$entry" "$NFS_EXPORTS" 2>/dev/null; then
            debug "NFS export already exists: $entry"
        else
            echo "$entry" >> "$NFS_EXPORTS"
            info "Added NFS export: $PXE_WEBROOT for $net"
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
