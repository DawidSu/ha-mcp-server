#!/bin/bash
# Circuit Breaker Pattern Implementation for Home Assistant MCP Server
# Provides fault tolerance and automatic recovery for external dependencies

set -euo pipefail

# Source logger if available
if [[ -f "/opt/scripts/logger.sh" ]]; then
    source "/opt/scripts/logger.sh"
else
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1" >&2; }
    log_info() { echo "[INFO] $1"; }
    log_critical() { echo "[CRITICAL] $1" >&2; }
fi

# =============================================================================
# Circuit Breaker Configuration
# =============================================================================

# Global circuit breaker states
declare -A CIRCUIT_BREAKER_STATES
declare -A CIRCUIT_BREAKER_FAILURES
declare -A CIRCUIT_BREAKER_LAST_FAILURE
declare -A CIRCUIT_BREAKER_SUCCESS_COUNT

# Circuit breaker constants
declare -g CB_STATE_CLOSED="CLOSED"
declare -g CB_STATE_OPEN="OPEN"
declare -g CB_STATE_HALF_OPEN="HALF_OPEN"

# Default configuration (can be overridden by environment variables)
declare -g CB_FAILURE_THRESHOLD="${CB_FAILURE_THRESHOLD:-5}"
declare -g CB_RECOVERY_TIMEOUT="${CB_RECOVERY_TIMEOUT:-60}"
declare -g CB_SUCCESS_THRESHOLD="${CB_SUCCESS_THRESHOLD:-3}"
declare -g CB_MONITORING_INTERVAL="${CB_MONITORING_INTERVAL:-10}"

# =============================================================================
# Circuit Breaker Core Functions
# =============================================================================

# Initialize circuit breaker for a service
cb_init() {
    local service_name="$1"
    
    CIRCUIT_BREAKER_STATES["$service_name"]="$CB_STATE_CLOSED"
    CIRCUIT_BREAKER_FAILURES["$service_name"]=0
    CIRCUIT_BREAKER_LAST_FAILURE["$service_name"]=0
    CIRCUIT_BREAKER_SUCCESS_COUNT["$service_name"]=0
    
    log_info "Circuit breaker initialized for service: $service_name"
}

# Get circuit breaker state
cb_get_state() {
    local service_name="$1"
    echo "${CIRCUIT_BREAKER_STATES[$service_name]:-$CB_STATE_CLOSED}"
}

# Check if circuit breaker allows operation
cb_can_execute() {
    local service_name="$1"
    local current_state=$(cb_get_state "$service_name")
    local current_time=$(date +%s)
    
    case "$current_state" in
        "$CB_STATE_CLOSED")
            return 0
            ;;
        "$CB_STATE_OPEN")
            local last_failure="${CIRCUIT_BREAKER_LAST_FAILURE[$service_name]:-0}"
            local time_since_failure=$((current_time - last_failure))
            
            if [[ "$time_since_failure" -ge "$CB_RECOVERY_TIMEOUT" ]]; then
                # Move to half-open state
                CIRCUIT_BREAKER_STATES["$service_name"]="$CB_STATE_HALF_OPEN"
                CIRCUIT_BREAKER_SUCCESS_COUNT["$service_name"]=0
                log_info "Circuit breaker for $service_name moved to HALF_OPEN state"
                return 0
            else
                log_warning "Circuit breaker for $service_name is OPEN (${time_since_failure}s since failure)"
                return 1
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            return 0
            ;;
        *)
            log_error "Invalid circuit breaker state: $current_state"
            return 1
            ;;
    esac
}

# Record successful operation
cb_record_success() {
    local service_name="$1"
    local current_state=$(cb_get_state "$service_name")
    
    case "$current_state" in
        "$CB_STATE_CLOSED")
            CIRCUIT_BREAKER_FAILURES["$service_name"]=0
            ;;
        "$CB_STATE_HALF_OPEN")
            local success_count="${CIRCUIT_BREAKER_SUCCESS_COUNT[$service_name]:-0}"
            ((success_count++))
            CIRCUIT_BREAKER_SUCCESS_COUNT["$service_name"]="$success_count"
            
            if [[ "$success_count" -ge "$CB_SUCCESS_THRESHOLD" ]]; then
                # Move back to closed state
                CIRCUIT_BREAKER_STATES["$service_name"]="$CB_STATE_CLOSED"
                CIRCUIT_BREAKER_FAILURES["$service_name"]=0
                log_info "Circuit breaker for $service_name moved back to CLOSED state"
            fi
            ;;
    esac
}

# Record failed operation
cb_record_failure() {
    local service_name="$1"
    local current_time=$(date +%s)
    local current_state=$(cb_get_state "$service_name")
    
    local failure_count="${CIRCUIT_BREAKER_FAILURES[$service_name]:-0}"
    ((failure_count++))
    CIRCUIT_BREAKER_FAILURES["$service_name"]="$failure_count"
    CIRCUIT_BREAKER_LAST_FAILURE["$service_name"]="$current_time"
    
    case "$current_state" in
        "$CB_STATE_CLOSED")
            if [[ "$failure_count" -ge "$CB_FAILURE_THRESHOLD" ]]; then
                CIRCUIT_BREAKER_STATES["$service_name"]="$CB_STATE_OPEN"
                log_critical "Circuit breaker for $service_name opened after $failure_count failures"
            else
                log_warning "Circuit breaker failure recorded for $service_name ($failure_count/$CB_FAILURE_THRESHOLD)"
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            # Failed in half-open state, move back to open
            CIRCUIT_BREAKER_STATES["$service_name"]="$CB_STATE_OPEN"
            log_warning "Circuit breaker for $service_name failed in HALF_OPEN state, moving back to OPEN"
            ;;
    esac
}

# Execute command with circuit breaker protection
cb_execute() {
    local service_name="$1"
    shift
    local command="$@"
    
    # Initialize circuit breaker if not exists
    if [[ -z "${CIRCUIT_BREAKER_STATES[$service_name]:-}" ]]; then
        cb_init "$service_name"
    fi
    
    # Check if execution is allowed
    if ! cb_can_execute "$service_name"; then
        log_warning "Circuit breaker prevented execution for service: $service_name"
        return 1
    fi
    
    # Execute command with timeout
    local start_time=$(date +%s)
    if timeout 30 bash -c "$command"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_info "Command succeeded for $service_name (${duration}s)"
        cb_record_success "$service_name"
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "Command failed for $service_name after ${duration}s (exit code: $exit_code)"
        cb_record_failure "$service_name"
        return $exit_code
    fi
}

# =============================================================================
# Service-Specific Circuit Breakers
# =============================================================================

# Home Assistant service circuit breaker
cb_homeassistant() {
    local action="$1"
    shift
    
    case "$action" in
        "check_config")
            cb_execute "homeassistant" "ha core check" "$@"
            ;;
        "restart")
            cb_execute "homeassistant" "ha core restart" "$@"
            ;;
        "validate_yaml")
            local file="$1"
            cb_execute "homeassistant_yaml" "python3 -c \"import yaml; yaml.safe_load(open('$file'))\"" "$@"
            ;;
        *)
            log_error "Unknown Home Assistant action: $action"
            return 1
            ;;
    esac
}

# Docker service circuit breaker
cb_docker() {
    local action="$1"
    shift
    
    case "$action" in
        "ps")
            cb_execute "docker" "docker ps" "$@"
            ;;
        "restart")
            local container="$1"
            cb_execute "docker" "docker restart '$container'" "$@"
            ;;
        "logs")
            local container="$1"
            cb_execute "docker" "docker logs --tail=50 '$container'" "$@"
            ;;
        *)
            log_error "Unknown Docker action: $action"
            return 1
            ;;
    esac
}

# File system circuit breaker
cb_filesystem() {
    local action="$1"
    shift
    
    case "$action" in
        "check_space")
            local path="$1"
            cb_execute "filesystem" "df -h '$path'" "$@"
            ;;
        "check_permissions")
            local path="$1"
            cb_execute "filesystem" "test -r '$path' && test -w '$path'" "$@"
            ;;
        "backup")
            local source="$1"
            local dest="$2"
            cb_execute "filesystem_backup" "cp -r '$source' '$dest'" "$@"
            ;;
        *)
            log_error "Unknown filesystem action: $action"
            return 1
            ;;
    esac
}

# =============================================================================
# Recovery Functions
# =============================================================================

# Automatic recovery for different error types
cb_auto_recover() {
    local service_name="$1"
    local error_type="${2:-general}"
    
    log_info "Attempting automatic recovery for $service_name (error type: $error_type)"
    
    case "$error_type" in
        "process_dead")
            if [[ "$service_name" == *"mcp"* ]]; then
                log_info "Attempting to restart MCP server process"
                if command -v systemctl >/dev/null 2>&1; then
                    cb_execute "recovery" "systemctl restart ha-mcp-server" || \
                    cb_execute "recovery" "docker-compose restart ha-mcp-server"
                else
                    cb_execute "recovery" "docker-compose restart ha-mcp-server"
                fi
            fi
            ;;
        "high_memory")
            log_info "Restarting service due to memory issues"
            cb_execute "recovery" "docker-compose restart ha-mcp-server"
            ;;
        "disk_full")
            log_info "Running cleanup due to disk space issues"
            cb_execute "recovery" "/opt/scripts/backup.sh cleanup"
            cb_execute "recovery" "docker system prune -f"
            ;;
        "network_timeout")
            log_info "Checking network connectivity"
            cb_execute "recovery" "ping -c 3 8.8.8.8" || \
            log_warning "Network connectivity issues detected"
            ;;
        *)
            log_info "Generic recovery: restarting service"
            cb_execute "recovery" "docker-compose restart ha-mcp-server"
            ;;
    esac
}

# =============================================================================
# Monitoring and Reporting
# =============================================================================

# Get circuit breaker status report
cb_status_report() {
    local output=""
    
    output+="Circuit Breaker Status Report\n"
    output+="================================\n"
    output+="Generated at: $(date)\n\n"
    
    for service in "${!CIRCUIT_BREAKER_STATES[@]}"; do
        local state="${CIRCUIT_BREAKER_STATES[$service]}"
        local failures="${CIRCUIT_BREAKER_FAILURES[$service]}"
        local last_failure="${CIRCUIT_BREAKER_LAST_FAILURE[$service]}"
        local success_count="${CIRCUIT_BREAKER_SUCCESS_COUNT[$service]}"
        
        output+="Service: $service\n"
        output+="  State: $state\n"
        output+="  Failures: $failures\n"
        output+="  Success Count: $success_count\n"
        
        if [[ "$last_failure" -gt 0 ]]; then
            local last_failure_ago=$(($(date +%s) - last_failure))
            output+="  Last Failure: ${last_failure_ago}s ago\n"
        fi
        
        output+="\n"
    done
    
    echo -e "$output"
}

# Monitor circuit breakers continuously
cb_monitor() {
    log_info "Starting circuit breaker monitoring (interval: ${CB_MONITORING_INTERVAL}s)"
    
    while true; do
        # Check for any open circuit breakers
        local open_circuits=0
        for service in "${!CIRCUIT_BREAKER_STATES[@]}"; do
            local state="${CIRCUIT_BREAKER_STATES[$service]}"
            if [[ "$state" == "$CB_STATE_OPEN" ]]; then
                ((open_circuits++))
                log_warning "Circuit breaker OPEN for service: $service"
                
                # Attempt automatic recovery
                cb_auto_recover "$service"
            fi
        done
        
        if [[ "$open_circuits" -eq 0 ]]; then
            log_info "All circuit breakers healthy"
        fi
        
        sleep "$CB_MONITORING_INTERVAL"
    done
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    case "${1:-}" in
        "init")
            cb_init "${2:-default}"
            ;;
        "execute")
            cb_execute "${2:-default}" "${@:3}"
            ;;
        "homeassistant")
            cb_homeassistant "${@:2}"
            ;;
        "docker")
            cb_docker "${@:2}"
            ;;
        "filesystem")
            cb_filesystem "${@:2}"
            ;;
        "status")
            cb_status_report
            ;;
        "monitor")
            cb_monitor
            ;;
        "test")
            echo "Testing circuit breaker functionality..."
            
            # Test initialization
            cb_init "test_service"
            echo "✓ Circuit breaker initialized"
            
            # Test successful execution
            cb_execute "test_service" "echo 'success'"
            echo "✓ Successful execution recorded"
            
            # Test failure recording
            cb_execute "test_service" "false" || true
            echo "✓ Failure recorded"
            
            # Show status
            cb_status_report
            ;;
        *)
            echo "Usage: $0 {init|execute|homeassistant|docker|filesystem|status|monitor|test} [args...]"
            echo ""
            echo "Commands:"
            echo "  init <service>                   - Initialize circuit breaker for service"
            echo "  execute <service> <command>      - Execute command with circuit breaker protection"
            echo "  homeassistant <action> [args]    - Home Assistant specific actions"
            echo "  docker <action> [args]           - Docker specific actions"
            echo "  filesystem <action> [args]       - Filesystem specific actions"
            echo "  status                           - Show circuit breaker status report"
            echo "  monitor                          - Start continuous monitoring"
            echo "  test                             - Run functionality tests"
            exit 1
            ;;
    esac
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f cb_init
    export -f cb_execute
    export -f cb_homeassistant
    export -f cb_docker
    export -f cb_filesystem
    export -f cb_status_report
    export -f cb_auto_recover
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi