#!/usr/bin/env bash
# lib/logging.sh - Structured logging with levels, colors, and file output

# Configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-/var/log/pxe-setup.log}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"

# Get numeric value for log level
_get_log_level_num() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# Get color for log level
_get_log_color() {
    case "$1" in
        DEBUG) echo "\033[0;36m" ;;  # Cyan
        INFO)  echo "\033[0;32m" ;;  # Green
        WARN)  echo "\033[0;33m" ;;  # Yellow
        ERROR) echo "\033[0;31m" ;;  # Red
        *)     echo "" ;;
    esac
}

# Reset color
_LOG_RESET="\033[0m"

# Check if stdout is a terminal (for color support)
_use_colors() {
    [[ -t 1 ]]
}

# Core logging function
_log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Check if we should log this level
    local level_num
    level_num=$(_get_log_level_num "$level")
    local threshold
    threshold=$(_get_log_level_num "$LOG_LEVEL")
    [[ $level_num -lt $threshold ]] && return 0
    
    # Format the message
    local formatted="$ts [$level] $msg"
    
    # Output to console (with colors if terminal)
    if _use_colors; then
        local color
        color=$(_get_log_color "$level")
        if [[ "$level" == "ERROR" ]]; then
            echo -e "${color}${formatted}${_LOG_RESET}" >&2
        else
            echo -e "${color}${formatted}${_LOG_RESET}"
        fi
    else
        if [[ "$level" == "ERROR" ]]; then
            echo "$formatted" >&2
        else
            echo "$formatted"
        fi
    fi
    
    # Append to log file (without colors)
    if [[ "$LOG_TO_FILE" == true ]] && [[ -n "$LOG_FILE" ]]; then
        # Create log directory if needed
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || true
        echo "$formatted" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Convenience functions for each log level
debug() { _log DEBUG "$*"; }
info()  { _log INFO "$*"; }
warn()  { _log WARN "$*"; }
error() { _log ERROR "$*"; }

# Fatal error - log and exit
abort() {
    error "$*"
    exit 1
}

# Log a separator line
log_separator() {
    info "═══════════════════════════════════════════════════════════════"
}

# Log a step header
log_step() {
    info "▶ $*"
}

# Log success
log_success() {
    info "✓ $*"
}

# Log skip
log_skip() {
    info "⏭ $*"
}
