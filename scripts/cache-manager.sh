#!/bin/bash
# Cache Manager for Home Assistant MCP Server
# Provides file-based caching for frequently accessed data and operations

set -euo pipefail

# Source logger if available
if [[ -f "/opt/scripts/logger.sh" ]]; then
    source "/opt/scripts/logger.sh"
else
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1" >&2; }
    log_info() { echo "[INFO] $1"; }
    log_debug() { echo "[DEBUG] $1"; }
fi

# =============================================================================
# Cache Configuration
# =============================================================================

# Cache directories
declare -g CACHE_ROOT_DIR="${CACHE_ROOT_DIR:-/tmp/mcp-cache}"
declare -g CACHE_DATA_DIR="$CACHE_ROOT_DIR/data"
declare -g CACHE_META_DIR="$CACHE_ROOT_DIR/meta"
declare -g CACHE_STATS_DIR="$CACHE_ROOT_DIR/stats"

# Cache settings
declare -g CACHE_DEFAULT_TTL="${CACHE_DEFAULT_TTL:-300}"      # 5 minutes
declare -g CACHE_MAX_SIZE="${CACHE_MAX_SIZE:-104857600}"      # 100MB
declare -g CACHE_MAX_ENTRIES="${CACHE_MAX_ENTRIES:-10000}"    # Max number of cache entries
declare -g CACHE_CLEANUP_INTERVAL="${CACHE_CLEANUP_INTERVAL:-3600}"  # 1 hour
declare -g CACHE_ENABLED="${CACHE_ENABLED:-true}"

# Cache statistics
declare -A CACHE_STATS
CACHE_STATS["hits"]=0
CACHE_STATS["misses"]=0
CACHE_STATS["sets"]=0
CACHE_STATS["deletes"]=0
CACHE_STATS["evictions"]=0

# =============================================================================
# Core Cache Functions
# =============================================================================

# Initialize cache system
cache_init() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        log_info "Cache is disabled"
        return 0
    fi
    
    # Create cache directories
    mkdir -p "$CACHE_DATA_DIR" "$CACHE_META_DIR" "$CACHE_STATS_DIR"
    
    # Set permissions
    chmod 755 "$CACHE_ROOT_DIR" "$CACHE_DATA_DIR" "$CACHE_META_DIR" "$CACHE_STATS_DIR"
    
    # Load existing statistics
    cache_load_stats
    
    log_info "Cache initialized at: $CACHE_ROOT_DIR"
    log_debug "Cache TTL: ${CACHE_DEFAULT_TTL}s, Max size: ${CACHE_MAX_SIZE} bytes"
}

# Generate cache key hash
cache_key_hash() {
    local key="$1"
    # Use simple hash for compatibility (avoid requiring external tools)
    echo -n "$key" | cksum | awk '{print $1}'
}

# Get cache file paths
cache_get_paths() {
    local key="$1"
    local key_hash=$(cache_key_hash "$key")
    
    echo "$CACHE_DATA_DIR/$key_hash"      # Data file
    echo "$CACHE_META_DIR/$key_hash"      # Metadata file
}

# Check if cache entry exists and is valid
cache_is_valid() {
    local key="$1"
    local ttl="${2:-$CACHE_DEFAULT_TTL}"
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 1
    fi
    
    local paths=($(cache_get_paths "$key"))
    local data_file="${paths[0]}"
    local meta_file="${paths[1]}"
    
    # Check if files exist
    if [[ ! -f "$data_file" || ! -f "$meta_file" ]]; then
        return 1
    fi
    
    # Read metadata
    local created_time
    if ! created_time=$(cat "$meta_file" 2>/dev/null); then
        return 1
    fi
    
    # Check if entry has expired
    local current_time=$(date +%s)
    local age=$((current_time - created_time))
    
    if [[ $age -gt $ttl ]]; then
        log_debug "Cache entry expired: $key (age: ${age}s, ttl: ${ttl}s)"
        cache_delete "$key"
        return 1
    fi
    
    return 0
}

# Set cache entry
cache_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-$CACHE_DEFAULT_TTL}"
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    cache_init  # Ensure cache is initialized
    
    local paths=($(cache_get_paths "$key"))
    local data_file="${paths[0]}"
    local meta_file="${paths[1]}"
    
    # Check cache size before adding
    if ! cache_check_size_limit; then
        cache_cleanup_lru
    fi
    
    # Write data and metadata
    local current_time=$(date +%s)
    
    # Atomic write using temp files
    local temp_data="$data_file.tmp.$$"
    local temp_meta="$meta_file.tmp.$$"
    
    if echo "$value" > "$temp_data" && echo "$current_time" > "$temp_meta"; then
        mv "$temp_data" "$data_file"
        mv "$temp_meta" "$meta_file"
        
        ((CACHE_STATS["sets"]++))
        log_debug "Cache set: $key (ttl: ${ttl}s)"
        cache_save_stats
        return 0
    else
        rm -f "$temp_data" "$temp_meta"
        log_error "Failed to write cache entry: $key"
        return 1
    fi
}

# Get cache entry
cache_get() {
    local key="$1"
    local ttl="${2:-$CACHE_DEFAULT_TTL}"
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 1
    fi
    
    if cache_is_valid "$key" "$ttl"; then
        local paths=($(cache_get_paths "$key"))
        local data_file="${paths[0]}"
        
        if cat "$data_file" 2>/dev/null; then
            ((CACHE_STATS["hits"]++))
            log_debug "Cache hit: $key"
            
            # Update access time for LRU
            touch "$data_file"
            cache_save_stats
            return 0
        fi
    fi
    
    ((CACHE_STATS["misses"]++))
    log_debug "Cache miss: $key"
    cache_save_stats
    return 1
}

# Delete cache entry
cache_delete() {
    local key="$1"
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local paths=($(cache_get_paths "$key"))
    local data_file="${paths[0]}"
    local meta_file="${paths[1]}"
    
    local deleted=false
    if [[ -f "$data_file" ]]; then
        rm -f "$data_file"
        deleted=true
    fi
    
    if [[ -f "$meta_file" ]]; then
        rm -f "$meta_file"
        deleted=true
    fi
    
    if [[ "$deleted" == "true" ]]; then
        ((CACHE_STATS["deletes"]++))
        log_debug "Cache delete: $key"
        cache_save_stats
    fi
    
    return 0
}

# =============================================================================
# Cache Management Functions
# =============================================================================

# Check if cache size is within limits
cache_check_size_limit() {
    if [[ ! -d "$CACHE_DATA_DIR" ]]; then
        return 0
    fi
    
    local total_size
    if command -v du >/dev/null 2>&1; then
        total_size=$(du -sb "$CACHE_DATA_DIR" 2>/dev/null | cut -f1)
    else
        # Fallback: count files (approximate)
        local file_count
        file_count=$(find "$CACHE_DATA_DIR" -type f 2>/dev/null | wc -l)
        total_size=$((file_count * 1024))  # Estimate 1KB per file
    fi
    
    if [[ $total_size -gt $CACHE_MAX_SIZE ]]; then
        log_warning "Cache size limit exceeded: $total_size bytes (max: $CACHE_MAX_SIZE)"
        return 1
    fi
    
    return 0
}

# Check if entry count is within limits
cache_check_entry_limit() {
    if [[ ! -d "$CACHE_DATA_DIR" ]]; then
        return 0
    fi
    
    local entry_count
    entry_count=$(find "$CACHE_DATA_DIR" -type f 2>/dev/null | wc -l)
    
    if [[ $entry_count -gt $CACHE_MAX_ENTRIES ]]; then
        log_warning "Cache entry limit exceeded: $entry_count entries (max: $CACHE_MAX_ENTRIES)"
        return 1
    fi
    
    return 0
}

# Cleanup expired entries
cache_cleanup_expired() {
    if [[ "$CACHE_ENABLED" != "true" || ! -d "$CACHE_DATA_DIR" ]]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    local expired_count=0
    
    # Find all metadata files
    find "$CACHE_META_DIR" -name "*" -type f 2>/dev/null | while read -r meta_file; do
        if [[ -f "$meta_file" ]]; then
            local created_time
            if created_time=$(cat "$meta_file" 2>/dev/null); then
                local age=$((current_time - created_time))
                
                if [[ $age -gt $CACHE_DEFAULT_TTL ]]; then
                    # Extract key hash from filename
                    local key_hash=$(basename "$meta_file")
                    local data_file="$CACHE_DATA_DIR/$key_hash"
                    
                    rm -f "$meta_file" "$data_file"
                    ((expired_count++))
                fi
            else
                # Invalid metadata file
                rm -f "$meta_file"
                local key_hash=$(basename "$meta_file")
                local data_file="$CACHE_DATA_DIR/$key_hash"
                rm -f "$data_file"
                ((expired_count++))
            fi
        fi
    done
    
    if [[ $expired_count -gt 0 ]]; then
        log_info "Cleaned up $expired_count expired cache entries"
        CACHE_STATS["evictions"]=$((CACHE_STATS["evictions"] + expired_count))
        cache_save_stats
    fi
}

# Cleanup using LRU (Least Recently Used) strategy
cache_cleanup_lru() {
    if [[ "$CACHE_ENABLED" != "true" || ! -d "$CACHE_DATA_DIR" ]]; then
        return 0
    fi
    
    log_info "Running LRU cache cleanup..."
    
    # Get files sorted by access time (oldest first)
    local files_to_remove=()
    mapfile -t files_to_remove < <(find "$CACHE_DATA_DIR" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -n 100 | cut -d' ' -f2-)
    
    local removed_count=0
    for data_file in "${files_to_remove[@]}"; do
        if [[ -f "$data_file" ]]; then
            # Get corresponding meta file
            local key_hash=$(basename "$data_file")
            local meta_file="$CACHE_META_DIR/$key_hash"
            
            rm -f "$data_file" "$meta_file"
            ((removed_count++))
            
            # Check if we're now within limits
            if cache_check_size_limit && cache_check_entry_limit; then
                break
            fi
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log_info "LRU cleanup removed $removed_count cache entries"
        CACHE_STATS["evictions"]=$((CACHE_STATS["evictions"] + removed_count))
        cache_save_stats
    fi
}

# Clear entire cache
cache_clear() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local entry_count=0
    if [[ -d "$CACHE_DATA_DIR" ]]; then
        entry_count=$(find "$CACHE_DATA_DIR" -type f 2>/dev/null | wc -l)
        rm -rf "$CACHE_DATA_DIR"/*
    fi
    
    if [[ -d "$CACHE_META_DIR" ]]; then
        rm -rf "$CACHE_META_DIR"/*
    fi
    
    log_info "Cache cleared ($entry_count entries removed)"
    
    # Reset statistics
    CACHE_STATS["hits"]=0
    CACHE_STATS["misses"]=0
    CACHE_STATS["sets"]=0
    CACHE_STATS["deletes"]=$((CACHE_STATS["deletes"] + entry_count))
    CACHE_STATS["evictions"]=$((CACHE_STATS["evictions"] + entry_count))
    cache_save_stats
}

# =============================================================================
# Statistics Functions
# =============================================================================

# Save cache statistics
cache_save_stats() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local stats_file="$CACHE_STATS_DIR/stats"
    
    {
        echo "hits=${CACHE_STATS["hits"]}"
        echo "misses=${CACHE_STATS["misses"]}"
        echo "sets=${CACHE_STATS["sets"]}"
        echo "deletes=${CACHE_STATS["deletes"]}"
        echo "evictions=${CACHE_STATS["evictions"]}"
        echo "last_update=$(date +%s)"
    } > "$stats_file"
}

# Load cache statistics
cache_load_stats() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local stats_file="$CACHE_STATS_DIR/stats"
    
    if [[ -f "$stats_file" ]]; then
        while IFS='=' read -r key value; do
            if [[ -n "$key" && -n "$value" ]]; then
                case "$key" in
                    hits|misses|sets|deletes|evictions)
                        CACHE_STATS["$key"]="$value"
                        ;;
                esac
            fi
        done < "$stats_file"
    fi
}

# Get cache statistics
cache_get_stats() {
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        echo "Cache is disabled"
        return 0
    fi
    
    cache_init
    
    local total_requests=$((CACHE_STATS["hits"] + CACHE_STATS["misses"]))
    local hit_rate=0
    
    if [[ $total_requests -gt 0 ]]; then
        hit_rate=$(( (CACHE_STATS["hits"] * 100) / total_requests ))
    fi
    
    # Get current cache size and entry count
    local cache_size=0
    local entry_count=0
    
    if [[ -d "$CACHE_DATA_DIR" ]]; then
        if command -v du >/dev/null 2>&1; then
            cache_size=$(du -sb "$CACHE_DATA_DIR" 2>/dev/null | cut -f1 || echo "0")
        fi
        entry_count=$(find "$CACHE_DATA_DIR" -type f 2>/dev/null | wc -l || echo "0")
    fi
    
    # Format size for human readability
    local cache_size_human
    if command -v numfmt >/dev/null 2>&1; then
        cache_size_human=$(numfmt --to=iec "$cache_size")
    else
        cache_size_human="${cache_size} bytes"
    fi
    
    cat << EOF
Cache Statistics
================
Status: $([[ "$CACHE_ENABLED" == "true" ]] && echo "Enabled" || echo "Disabled")
Hit Rate: ${hit_rate}%
Total Requests: $total_requests
Hits: ${CACHE_STATS["hits"]}
Misses: ${CACHE_STATS["misses"]}
Sets: ${CACHE_STATS["sets"]}
Deletes: ${CACHE_STATS["deletes"]}
Evictions: ${CACHE_STATS["evictions"]}

Current State
=============
Entries: $entry_count / $CACHE_MAX_ENTRIES
Size: $cache_size_human / $(numfmt --to=iec $CACHE_MAX_SIZE 2>/dev/null || echo "${CACHE_MAX_SIZE} bytes")
TTL: ${CACHE_DEFAULT_TTL}s
Location: $CACHE_ROOT_DIR
EOF
}

# =============================================================================
# High-Level Cache Functions
# =============================================================================

# Cache command output
cache_command() {
    local cache_key="$1"
    local ttl="$2"
    shift 2
    local command="$*"
    
    # Try to get from cache first
    if cache_get "$cache_key" "$ttl"; then
        return 0
    fi
    
    # Execute command and cache result
    local output
    if output=$(eval "$command" 2>&1); then
        cache_set "$cache_key" "$output" "$ttl"
        echo "$output"
        return 0
    else
        local exit_code=$?
        # Don't cache errors
        echo "$output" >&2
        return $exit_code
    fi
}

# Cache file content
cache_file_content() {
    local file_path="$1"
    local ttl="${2:-$CACHE_DEFAULT_TTL}"
    
    local cache_key="file:$file_path"
    
    # Check if file was modified since cached
    if [[ -f "$file_path" ]]; then
        local file_mtime=$(stat -c %Y "$file_path" 2>/dev/null || stat -f %m "$file_path" 2>/dev/null || echo "0")
        cache_key="file:$file_path:$file_mtime"
    fi
    
    # Try to get from cache
    if cache_get "$cache_key" "$ttl"; then
        return 0
    fi
    
    # Read file and cache content
    if [[ -f "$file_path" ]]; then
        local content
        if content=$(cat "$file_path"); then
            cache_set "$cache_key" "$content" "$ttl"
            echo "$content"
            return 0
        fi
    fi
    
    return 1
}

# =============================================================================
# Background Cache Manager
# =============================================================================

# Start cache manager daemon
cache_daemon() {
    log_info "Starting cache manager daemon (cleanup interval: ${CACHE_CLEANUP_INTERVAL}s)"
    
    while true; do
        # Periodic cleanup
        cache_cleanup_expired
        
        # Check size and entry limits
        if ! cache_check_size_limit || ! cache_check_entry_limit; then
            cache_cleanup_lru
        fi
        
        sleep "$CACHE_CLEANUP_INTERVAL"
    done
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    case "${1:-}" in
        "init")
            cache_init
            ;;
        "set")
            cache_set "${2:-}" "${3:-}" "${4:-$CACHE_DEFAULT_TTL}"
            ;;
        "get")
            cache_get "${2:-}" "${3:-$CACHE_DEFAULT_TTL}"
            ;;
        "delete")
            cache_delete "${2:-}"
            ;;
        "clear")
            cache_clear
            ;;
        "stats")
            cache_get_stats
            ;;
        "cleanup")
            cache_cleanup_expired
            cache_cleanup_lru
            ;;
        "daemon")
            cache_daemon
            ;;
        "command")
            cache_command "${2:-}" "${3:-$CACHE_DEFAULT_TTL}" "${@:4}"
            ;;
        "file")
            cache_file_content "${2:-}" "${3:-$CACHE_DEFAULT_TTL}"
            ;;
        "test")
            echo "Testing cache functionality..."
            cache_init
            
            # Test set/get
            cache_set "test_key" "test_value" 10
            if result=$(cache_get "test_key"); then
                echo "✓ Cache set/get working: $result"
            else
                echo "✗ Cache set/get failed"
            fi
            
            # Test command caching
            cache_command "date_cmd" 5 "date"
            echo "✓ Command caching test completed"
            
            # Show stats
            cache_get_stats
            ;;
        *)
            echo "Usage: $0 {init|set|get|delete|clear|stats|cleanup|daemon|command|file|test}"
            echo ""
            echo "Commands:"
            echo "  init                              - Initialize cache system"
            echo "  set <key> <value> [ttl]          - Set cache entry"
            echo "  get <key> [ttl]                  - Get cache entry"
            echo "  delete <key>                     - Delete cache entry"
            echo "  clear                            - Clear entire cache"
            echo "  stats                            - Show cache statistics"
            echo "  cleanup                          - Run cache cleanup"
            echo "  daemon                           - Start cache manager daemon"
            echo "  command <key> <ttl> <command>    - Cache command output"
            echo "  file <path> [ttl]                - Cache file content"
            echo "  test                             - Run functionality test"
            exit 1
            ;;
    esac
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f cache_init cache_set cache_get cache_delete cache_clear
    export -f cache_get_stats cache_command cache_file_content
    export -f cache_cleanup_expired cache_cleanup_lru
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi