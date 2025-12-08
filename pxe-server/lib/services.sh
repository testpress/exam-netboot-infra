#!/usr/bin/env bash
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
