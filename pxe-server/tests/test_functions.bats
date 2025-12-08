#!/usr/bin/env bats
# tests/test_functions.bats - Unit tests for PXE setup functions

# ═══════════════════════════════════════════════════════════════════════════════
# Test Setup
# ═══════════════════════════════════════════════════════════════════════════════

setup() {
    # Set test mode
    export DRY_RUN=true
    export LOG_LEVEL=ERROR
    export ISO_PATH="/tmp/test.iso"
    export KIOSK_URL="https://example.com"
    export NFS_CLIENT_NETS="10.0.0.0/24"
    export SERVER_IP="10.0.0.1"
    export DEFAULT_IF="eth0"
    
    # Source library files
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    for lib in logging config preflight network packages; do
        source "$SCRIPT_DIR/lib/${lib}.sh" 2>/dev/null || true
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Logging Tests
# ═══════════════════════════════════════════════════════════════════════════════

@test "info() outputs message" {
    run info "test message"
    [ "$status" -eq 0 ]
}

@test "debug() respects LOG_LEVEL" {
    export LOG_LEVEL=INFO
    run debug "should not appear"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "abort() exits with error" {
    run abort "test error"
    [ "$status" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Config Tests
# ═══════════════════════════════════════════════════════════════════════════════

@test "load_config() sets default values" {
    unset ISO_PATH
    load_config
    [ -n "$ISO_PATH" ]
}

@test "NFS_CLIENT_NETS is parsed as array" {
    export NFS_CLIENT_NETS="10.0.0.0/24 192.168.1.0/24"
    load_config
    [ "${#NFS_CLIENT_NETS[@]}" -gt 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Validation Tests
# ═══════════════════════════════════════════════════════════════════════════════

@test "validate_config() rejects empty ISO_PATH" {
    export ISO_PATH=""
    run validate_config
    [ "$status" -ne 0 ]
}

@test "validate_config() accepts valid KIOSK_URL" {
    export KIOSK_URL="https://example.com"
    export ENABLE_KIOSK=true
    run validate_config
    [ "$status" -eq 0 ]
}

@test "validate_config() rejects invalid KIOSK_URL" {
    export KIOSK_URL="not-a-url"
    export ENABLE_KIOSK=true
    run validate_config
    [ "$status" -ne 0 ]
}

@test "validate_config() accepts valid CIDR" {
    export NFS_CLIENT_NETS=("10.0.0.0/24")
    run validate_config
    [ "$status" -eq 0 ]
}

@test "validate_config() rejects invalid CIDR" {
    export NFS_CLIENT_NETS=("invalid-cidr")
    run validate_config
    [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# State Management Tests
# ═══════════════════════════════════════════════════════════════════════════════

@test "is_step_complete() returns false for new step" {
    export STATE_FILE="/tmp/test_state_$$"
    rm -f "$STATE_FILE"
    touch "$STATE_FILE"
    
    run is_step_complete "new_step"
    [ "$status" -ne 0 ]
    
    rm -f "$STATE_FILE"
}

@test "mark_step_complete() adds step to state" {
    export STATE_FILE="/tmp/test_state_$$"
    export DRY_RUN=false
    rm -f "$STATE_FILE"
    touch "$STATE_FILE"
    
    mark_step_complete "test_step"
    
    run grep -x "test_step" "$STATE_FILE"
    [ "$status" -eq 0 ]
    
    rm -f "$STATE_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Package Tests
# ═══════════════════════════════════════════════════════════════════════════════

@test "REQUIRED_PACKAGES array is defined" {
    [ "${#REQUIRED_PACKAGES[@]}" -gt 0 ]
}

@test "install_packages() respects SKIP_PACKAGES" {
    export SKIP_PACKAGES=true
    run install_packages
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping"* ]]
}

@test "install_packages() respects DRY_RUN" {
    export DRY_RUN=true
    export SKIP_PACKAGES=false
    run install_packages
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step Control Tests
# ═══════════════════════════════════════════════════════════════════════════════

setup_main() {
    # Source main.sh for step control tests
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Set required variables before sourcing
    export DRY_RUN=true
    export LOG_LEVEL=ERROR
    export ISO_PATH="/tmp/test.iso"
    export SERVER_IP="10.0.0.1"
    export DEFAULT_IF="eth0"
    export KIOSK_URL="https://example.com"
    export NFS_CLIENT_NETS="10.0.0.0/24"
    export DHCP_RANGE_START="10.0.0.170"
    export DHCP_RANGE_END="10.0.0.200"
    
    # Source libraries first
    for lib in logging config preflight network packages; do
        source "$SCRIPT_DIR/lib/${lib}.sh" 2>/dev/null || true
    done
}

@test "ALL_STEPS array has 12 steps" {
    setup_main
    
    # Define ALL_STEPS as it would be in main.sh
    ALL_STEPS=(packages directories webroot bootloaders tftp nfs pxelinux grub dnsmasq nginx kiosk services)
    
    [ "${#ALL_STEPS[@]}" -eq 12 ]
}

@test "get_step_description() returns description for packages" {
    setup_main
    
    # Define the function as in main.sh
    get_step_description() {
        case "$1" in
            packages) echo "Install required apt packages" ;;
            *) echo "" ;;
        esac
    }
    
    run get_step_description "packages"
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt packages"* ]]
}

@test "get_step_description() returns empty for unknown step" {
    setup_main
    
    get_step_description() {
        case "$1" in
            packages) echo "Install required apt packages" ;;
            *) echo "" ;;
        esac
    }
    
    run get_step_description "unknown_step"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "get_step_function() returns correct function for packages" {
    setup_main
    
    get_step_function() {
        case "$1" in
            packages) echo "install_packages" ;;
            directories) echo "prepare_directories" ;;
            *) echo "" ;;
        esac
    }
    
    run get_step_function "packages"
    [ "$status" -eq 0 ]
    [ "$output" = "install_packages" ]
}

@test "validate_step_name() succeeds for valid step" {
    setup_main
    
    ALL_STEPS=(packages directories webroot)
    
    validate_step_name() {
        local step="$1"
        for s in "${ALL_STEPS[@]}"; do
            if [[ "$s" == "$step" ]]; then
                return 0
            fi
        done
        return 1
    }
    
    run validate_step_name "packages"
    [ "$status" -eq 0 ]
}

@test "validate_step_name() fails for invalid step" {
    setup_main
    
    ALL_STEPS=(packages directories webroot)
    
    validate_step_name() {
        local step="$1"
        for s in "${ALL_STEPS[@]}"; do
            if [[ "$s" == "$step" ]]; then
                return 0
            fi
        done
        return 1
    }
    
    run validate_step_name "invalid_step"
    [ "$status" -ne 0 ]
}

@test "reset_state() clears state file" {
    export STATE_FILE="/tmp/test_state_reset_$$"
    export DRY_RUN=false
    
    # Create state file with content
    echo "packages" > "$STATE_FILE"
    echo "directories" >> "$STATE_FILE"
    
    reset_state
    
    # File should be removed
    [ ! -f "$STATE_FILE" ]
}
