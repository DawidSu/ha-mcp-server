#!/bin/bash
# Security utilities for Home Assistant MCP Server
# Provides input validation, sanitization, and security checks

set -euo pipefail

# Source logger if available
if [[ -f "/opt/scripts/logger.sh" ]]; then
    source "/opt/scripts/logger.sh"
else
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1" >&2; }
    log_info() { echo "[INFO] $1"; }
fi

# =============================================================================
# Input Validation Functions
# =============================================================================

# Validate configuration path to prevent directory traversal
validate_config_path() {
    local path="$1"
    
    # Remove any trailing slashes
    path="${path%/}"
    
    # Check for directory traversal attempts
    if [[ "$path" =~ \.\./|\.\.$ ]]; then
        log_error "Invalid config path: directory traversal detected"
        return 1
    fi
    
    # Ensure path starts with / (absolute path)
    if [[ ! "$path" =~ ^/ ]]; then
        log_error "Invalid config path: must be absolute path"
        return 1
    fi
    
    # Validate path characters (allow only safe characters)
    if [[ ! "$path" =~ ^/[a-zA-Z0-9_/-]+$ ]]; then
        log_error "Invalid config path format: contains unsafe characters"
        return 1
    fi
    
    # Check path length (reasonable limit)
    if [[ ${#path} -gt 255 ]]; then
        log_error "Invalid config path: too long (max 255 characters)"
        return 1
    fi
    
    return 0
}

# Validate log level
validate_log_level() {
    local level="$1"
    local valid_levels=("debug" "info" "warning" "error")
    
    # Convert to lowercase for comparison
    level=$(echo "$level" | tr '[:upper:]' '[:lower:]')
    
    for valid in "${valid_levels[@]}"; do
        if [[ "$level" == "$valid" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid log level: $level (must be: debug, info, warning, error)"
    return 1
}

# Validate file extension
validate_file_extension() {
    local file_path="$1"
    local allowed_extensions=("yaml" "yml" "json" "py" "md" "txt" "conf" "cfg" "ini" "log")
    
    # Extract extension
    local extension="${file_path##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    # Check if file has extension
    if [[ "$extension" == "$file_path" ]]; then
        log_error "File has no extension: $file_path"
        return 1
    fi
    
    # Check against allowed extensions
    for allowed in "${allowed_extensions[@]}"; do
        if [[ "$extension" == "$allowed" ]]; then
            return 0
        fi
    done
    
    log_error "Access denied: file extension '$extension' not allowed"
    log_info "Allowed extensions: ${allowed_extensions[*]}"
    return 1
}

# Validate file size
validate_file_size() {
    local file_path="$1"
    local max_size="${2:-10485760}"  # Default: 10MB
    
    if [[ -f "$file_path" ]]; then
        local file_size
        # Try different stat formats for compatibility
        if command -v stat >/dev/null 2>&1; then
            if stat -f%z "$file_path" >/dev/null 2>&1; then
                # BSD/macOS format
                file_size=$(stat -f%z "$file_path")
            elif stat -c%s "$file_path" >/dev/null 2>&1; then
                # GNU/Linux format
                file_size=$(stat -c%s "$file_path")
            else
                log_warning "Cannot determine file size for: $file_path"
                return 0  # Allow if we can't determine size
            fi
        else
            log_warning "stat command not available"
            return 0
        fi
        
        if [[ "$file_size" -gt "$max_size" ]]; then
            log_error "File too large: $file_size bytes (max: $max_size bytes)"
            return 1
        fi
    fi
    
    return 0
}

# Sanitize filename
sanitize_filename() {
    local filename="$1"
    
    # Remove or replace unsafe characters
    filename=$(echo "$filename" | sed 's/[^a-zA-Z0-9._-]/_/g')
    
    # Remove leading dots to prevent hidden files
    filename=$(echo "$filename" | sed 's/^\.*//')
    
    # Ensure filename is not empty after sanitization
    if [[ -z "$filename" ]]; then
        filename="sanitized_file"
    fi
    
    # Limit filename length
    if [[ ${#filename} -gt 100 ]]; then
        filename="${filename:0:97}..."
    fi
    
    echo "$filename"
}

# =============================================================================
# Rate Limiting Functions
# =============================================================================

declare -A REQUEST_COUNTS
declare -g RATE_LIMIT_WINDOW="${RATE_LIMIT_WINDOW:-60}"  # seconds
declare -g RATE_LIMIT_MAX="${RATE_LIMIT_MAX:-100}"      # requests per window
declare -g RATE_LIMIT_ENABLED="${RATE_LIMIT_ENABLED:-true}"

# Check rate limit for client
check_rate_limit() {
    local client_id="$1"
    
    if [[ "$RATE_LIMIT_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    local window_start=$((current_time - RATE_LIMIT_WINDOW))
    
    # Clean old entries
    for key in "${!REQUEST_COUNTS[@]}"; do
        if [[ "$key" =~ ^${client_id}_([0-9]+)$ ]]; then
            local timestamp="${BASH_REMATCH[1]}"
            if [[ "$timestamp" -lt "$window_start" ]]; then
                unset REQUEST_COUNTS["$key"]
            fi
        fi
    done
    
    # Count current requests in window
    local count=0
    for key in "${!REQUEST_COUNTS[@]}"; do
        if [[ "$key" =~ ^${client_id}_ ]]; then
            ((count++))
        fi
    done
    
    # Check limit
    if [[ "$count" -ge "$RATE_LIMIT_MAX" ]]; then
        log_warning "Rate limit exceeded for client: $client_id ($count/$RATE_LIMIT_MAX)"
        return 1
    fi
    
    # Record this request
    REQUEST_COUNTS["${client_id}_${current_time}"]=1
    return 0
}

# =============================================================================
# Security Checks
# =============================================================================

# Check if file is within allowed directory
check_file_in_allowed_path() {
    local file_path="$1"
    local allowed_base="${2:-/config}"
    
    # Resolve any symlinks and get absolute path
    if command -v realpath >/dev/null 2>&1; then
        file_path=$(realpath "$file_path" 2>/dev/null || echo "$file_path")
        allowed_base=$(realpath "$allowed_base" 2>/dev/null || echo "$allowed_base")
    fi
    
    # Check if file is within allowed base directory
    case "$file_path" in
        "$allowed_base"*)
            return 0
            ;;
        *)
            log_error "File access denied: $file_path not within allowed path $allowed_base"
            return 1
            ;;
    esac
}

# Check for suspicious file patterns
check_suspicious_patterns() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    
    # Suspicious patterns
    local suspicious_patterns=(
        ".*\.\..*"           # Directory traversal
        ".*password.*"       # Password files
        ".*secret.*"         # Secret files
        ".*key.*"           # Key files
        ".*token.*"         # Token files
        ".*\.ssh/.*"        # SSH files
        ".*\.gnupg/.*"      # GPG files
        "/etc/passwd"       # System password file
        "/etc/shadow"       # System shadow file
    )
    
    for pattern in "${suspicious_patterns[@]}"; do
        if [[ "$file_path" =~ $pattern ]] || [[ "$filename" =~ $pattern ]]; then
            log_warning "Suspicious file pattern detected: $file_path"
            return 1
        fi
    done
    
    return 0
}

# Comprehensive file validation
validate_file_access() {
    local file_path="$1"
    local allowed_base="${2:-/config}"
    local max_size="${3:-10485760}"
    
    # Run all validations
    validate_file_extension "$file_path" || return 1
    validate_file_size "$file_path" "$max_size" || return 1
    check_file_in_allowed_path "$file_path" "$allowed_base" || return 1
    check_suspicious_patterns "$file_path" || return 1
    
    return 0
}

# =============================================================================
# Export functions for use in other scripts
# =============================================================================

# Make functions available when script is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f validate_config_path
    export -f validate_log_level
    export -f validate_file_extension
    export -f validate_file_size
    export -f sanitize_filename
    export -f check_rate_limit
    export -f check_file_in_allowed_path
    export -f check_suspicious_patterns
    export -f validate_file_access
fi

# =============================================================================
# Main function for standalone usage
# =============================================================================

main() {
    case "${1:-}" in
        "validate-config")
            validate_config_path "${2:-}"
            ;;
        "validate-log-level")
            validate_log_level "${2:-}"
            ;;
        "validate-file")
            validate_file_access "${2:-}" "${3:-/config}" "${4:-10485760}"
            ;;
        "sanitize-filename")
            sanitize_filename "${2:-}"
            ;;
        "check-rate-limit")
            check_rate_limit "${2:-default}"
            ;;
        "test")
            echo "Running security utils tests..."
            
            # Test config path validation
            echo "Testing config path validation..."
            validate_config_path "/config" && echo "✓ Valid path accepted"
            ! validate_config_path "../../../etc" && echo "✓ Directory traversal blocked"
            ! validate_config_path "relative/path" && echo "✓ Relative path blocked"
            
            # Test file extension validation
            echo "Testing file extension validation..."
            validate_file_extension "test.yaml" && echo "✓ Valid extension accepted"
            ! validate_file_extension "test.exe" && echo "✓ Invalid extension blocked"
            
            echo "All tests completed"
            ;;
        *)
            echo "Usage: $0 {validate-config|validate-log-level|validate-file|sanitize-filename|check-rate-limit|test} [args...]"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi