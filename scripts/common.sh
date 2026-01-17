#!/bin/bash
# Common utilities library for MCP Server scripts
# Eliminates duplication across multiple scripts

set -euo pipefail

# Script directory detection - used by 7+ scripts
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

# Common logging fallback - used by 9+ scripts
setup_logging() {
    if [[ -f "/opt/scripts/logger.sh" ]]; then
        source "/opt/scripts/logger.sh"
    else
        log_error() { echo "[ERROR] $1" >&2; }
        log_warning() { echo "[WARNING] $1" >&2; }
        log_info() { echo "[INFO] $1"; }
        log_debug() { 
            if [[ "${LOG_LEVEL:-info}" == "debug" ]]; then
                echo "[DEBUG] $1"
            fi
        }
    fi
}

# Directory validation - used by 20+ instances
validate_directory() {
    local dir_path="$1"
    local dir_name="${2:-directory}"
    
    if [[ ! -d "$dir_path" ]]; then
        log_error "$dir_name not found: $dir_path"
        return 1
    fi
    
    if [[ ! -r "$dir_path" ]]; then
        log_error "$dir_name is not readable: $dir_path"
        return 1
    fi
    
    return 0
}

# File validation - common pattern
validate_file() {
    local file_path="$1"
    local file_name="${2:-file}"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "$file_name not found: $file_path"
        return 1
    fi
    
    if [[ ! -r "$file_path" ]]; then
        log_error "$file_name is not readable: $file_path"
        return 1
    fi
    
    return 0
}

# Environment setup - consolidate from multiple scripts
setup_environment() {
    export SCRIPT_DIR="${SCRIPT_DIR:-$(get_script_dir)}"
    export LOG_LEVEL="${LOG_LEVEL:-info}"
    export HA_CONFIG_PATH="${HA_CONFIG_PATH:-/config}"
    
    # Initialize logging
    setup_logging
}

# Common error handler
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Error on line $line_number (exit code: $exit_code)"
    exit $exit_code
}

# Set up error trapping - standardize across scripts
setup_error_handling() {
    trap 'handle_error $LINENO' ERR
}

# Utility for checking if running in container
is_container() {
    [[ -f "/.dockerenv" ]] || grep -sq 'docker\|lxc' /proc/1/cgroup 2>/dev/null
}

# Utility for checking if Home Assistant addon environment
is_ha_addon() {
    [[ -n "${HASSIO_TOKEN:-}" ]] || command -v bashio >/dev/null 2>&1
}

# Common initialization for all scripts
common_init() {
    setup_error_handling
    setup_environment
    
    log_debug "Script initialized: $(basename "${BASH_SOURCE[1]}")"
    log_debug "Environment: Container=$(is_container), HA_Addon=$(is_ha_addon)"
}

# Export functions for use in other scripts
export -f get_script_dir
export -f setup_logging  
export -f validate_directory
export -f validate_file
export -f setup_environment
export -f handle_error
export -f setup_error_handling
export -f is_container
export -f is_ha_addon
export -f common_init