#!/bin/bash
# Comprehensive Health Check System for Home Assistant MCP Server
# Provides detailed health monitoring and status reporting

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/logger.sh" ]]; then
    source "$SCRIPT_DIR/logger.sh"
else
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1" >&2; }
    log_info() { echo "[INFO] $1"; }
    log_debug() { echo "[DEBUG] $1"; }
fi

# Load circuit breaker if available
if [[ -f "$SCRIPT_DIR/circuit-breaker.sh" ]]; then
    source "$SCRIPT_DIR/circuit-breaker.sh"
fi

# =============================================================================
# Health Check Configuration
# =============================================================================

# Health check thresholds
declare -g HC_DISK_WARNING_THRESHOLD="${HC_DISK_WARNING_THRESHOLD:-80}"
declare -g HC_DISK_CRITICAL_THRESHOLD="${HC_DISK_CRITICAL_THRESHOLD:-90}"
declare -g HC_MEMORY_WARNING_THRESHOLD="${HC_MEMORY_WARNING_THRESHOLD:-80}"
declare -g HC_MEMORY_CRITICAL_THRESHOLD="${HC_MEMORY_CRITICAL_THRESHOLD:-95}"
declare -g HC_CPU_WARNING_THRESHOLD="${HC_CPU_WARNING_THRESHOLD:-80}"
declare -g HC_CPU_CRITICAL_THRESHOLD="${HC_CPU_CRITICAL_THRESHOLD:-95}"
declare -g HC_RESPONSE_TIME_WARNING="${HC_RESPONSE_TIME_WARNING:-5}"
declare -g HC_RESPONSE_TIME_CRITICAL="${HC_RESPONSE_TIME_CRITICAL:-10}"

# Health check configuration
declare -g HC_CONFIG_PATH="${HA_CONFIG_PATH:-/config}"
declare -g HC_TIMEOUT="${HC_TIMEOUT:-30}"
declare -g HC_OUTPUT_FORMAT="${HC_OUTPUT_FORMAT:-human}"  # human, json, prometheus

# Health status constants
declare -g HC_STATUS_OK="OK"
declare -g HC_STATUS_WARNING="WARNING"
declare -g HC_STATUS_CRITICAL="CRITICAL"
declare -g HC_STATUS_UNKNOWN="UNKNOWN"

# Global health state
declare -A HC_RESULTS

# =============================================================================
# Core Health Check Functions
# =============================================================================

# Initialize health check system
hc_init() {
    HC_RESULTS["overall"]="$HC_STATUS_UNKNOWN"
    HC_RESULTS["timestamp"]=$(date +%s)
    HC_RESULTS["checks_total"]=0
    HC_RESULTS["checks_passed"]=0
    HC_RESULTS["checks_warnings"]=0
    HC_RESULTS["checks_critical"]=0
}

# Record health check result
hc_record_result() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    local value="${4:-}"
    local unit="${5:-}"
    
    HC_RESULTS["${check_name}_status"]="$status"
    HC_RESULTS["${check_name}_message"]="$message"
    HC_RESULTS["${check_name}_value"]="$value"
    HC_RESULTS["${check_name}_unit"]="$unit"
    HC_RESULTS["${check_name}_timestamp"]=$(date +%s)
    
    # Update counters
    ((HC_RESULTS["checks_total"]++))
    
    case "$status" in
        "$HC_STATUS_OK")
            ((HC_RESULTS["checks_passed"]++))
            ;;
        "$HC_STATUS_WARNING")
            ((HC_RESULTS["checks_warnings"]++))
            ;;
        "$HC_STATUS_CRITICAL")
            ((HC_RESULTS["checks_critical"]++))
            ;;
    esac
    
    log_debug "Health check: $check_name = $status ($message)"
}

# Determine overall health status
hc_calculate_overall_status() {
    if [[ ${HC_RESULTS["checks_critical"]} -gt 0 ]]; then
        HC_RESULTS["overall"]="$HC_STATUS_CRITICAL"
    elif [[ ${HC_RESULTS["checks_warnings"]} -gt 0 ]]; then
        HC_RESULTS["overall"]="$HC_STATUS_WARNING"
    elif [[ ${HC_RESULTS["checks_passed"]} -gt 0 ]]; then
        HC_RESULTS["overall"]="$HC_STATUS_OK"
    else
        HC_RESULTS["overall"]="$HC_STATUS_UNKNOWN"
    fi
}

# =============================================================================
# Individual Health Checks
# =============================================================================

# Check MCP server process
hc_check_mcp_process() {
    local check_name="mcp_process"
    
    if pgrep -f "server-filesystem" > /dev/null; then
        local pid=$(pgrep -f "server-filesystem")
        local uptime
        if command -v ps >/dev/null 2>&1; then
            uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "unknown")
        else
            uptime="unknown"
        fi
        hc_record_result "$check_name" "$HC_STATUS_OK" "MCP server running (PID: $pid, uptime: $uptime)" "$pid" "pid"
    else
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "MCP server process not found" "" ""
    fi
}

# Check disk space
hc_check_disk_space() {
    local check_name="disk_space"
    local path="${1:-$HC_CONFIG_PATH}"
    
    if [[ ! -d "$path" ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Config directory not found: $path" "" ""
        return
    fi
    
    local usage_percent
    if command -v df >/dev/null 2>&1; then
        usage_percent=$(df -h "$path" | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    else
        hc_record_result "$check_name" "$HC_STATUS_UNKNOWN" "df command not available" "" ""
        return
    fi
    
    if [[ $usage_percent -ge $HC_DISK_CRITICAL_THRESHOLD ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Disk usage critical: ${usage_percent}%" "$usage_percent" "%"
    elif [[ $usage_percent -ge $HC_DISK_WARNING_THRESHOLD ]]; then
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "Disk usage high: ${usage_percent}%" "$usage_percent" "%"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "Disk usage normal: ${usage_percent}%" "$usage_percent" "%"
    fi
}

# Check memory usage
hc_check_memory_usage() {
    local check_name="memory_usage"
    
    local memory_percent
    if command -v free >/dev/null 2>&1; then
        memory_percent=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}' || echo "0")
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS alternative
        local page_size=$(vm_stat | grep "page size" | awk '{print $8}')
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
        local pages_total=$(vm_stat | grep -E "(Pages free|Pages active|Pages inactive|Pages speculative|Pages wired down)" | awk '{sum += $3} END {print sum}')
        memory_percent=$(( (pages_total - pages_free) * 100 / pages_total ))
    else
        hc_record_result "$check_name" "$HC_STATUS_UNKNOWN" "Memory check tools not available" "" ""
        return
    fi
    
    if [[ $memory_percent -ge $HC_MEMORY_CRITICAL_THRESHOLD ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Memory usage critical: ${memory_percent}%" "$memory_percent" "%"
    elif [[ $memory_percent -ge $HC_MEMORY_WARNING_THRESHOLD ]]; then
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "Memory usage high: ${memory_percent}%" "$memory_percent" "%"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "Memory usage normal: ${memory_percent}%" "$memory_percent" "%"
    fi
}

# Check CPU usage
hc_check_cpu_usage() {
    local check_name="cpu_usage"
    
    local cpu_percent
    if command -v top >/dev/null 2>&1; then
        # Get CPU usage over a short period
        cpu_percent=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $2}' | sed 's/%us,//' | sed 's/,//' || echo "0")
        
        # If that fails, try alternative method
        if [[ -z "$cpu_percent" || "$cpu_percent" == "0" ]]; then
            cpu_percent=$(grep 'cpu ' /proc/stat 2>/dev/null | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.0f", usage}' || echo "0")
        fi
    else
        hc_record_result "$check_name" "$HC_STATUS_UNKNOWN" "CPU monitoring tools not available" "" ""
        return
    fi
    
    # Remove any non-numeric characters
    cpu_percent=$(echo "$cpu_percent" | grep -o '[0-9]*' | head -1)
    cpu_percent=${cpu_percent:-0}
    
    if [[ $cpu_percent -ge $HC_CPU_CRITICAL_THRESHOLD ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "CPU usage critical: ${cpu_percent}%" "$cpu_percent" "%"
    elif [[ $cpu_percent -ge $HC_CPU_WARNING_THRESHOLD ]]; then
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "CPU usage high: ${cpu_percent}%" "$cpu_percent" "%"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "CPU usage normal: ${cpu_percent}%" "$cpu_percent" "%"
    fi
}

# Check configuration files
hc_check_config_files() {
    local check_name="config_files"
    local config_path="${1:-$HC_CONFIG_PATH}"
    
    if [[ ! -d "$config_path" ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Config directory not found: $config_path" "" ""
        return
    fi
    
    # Check for essential configuration files
    local essential_files=("configuration.yaml")
    local missing_files=()
    local found_files=0
    
    for file in "${essential_files[@]}"; do
        if [[ -f "$config_path/$file" ]]; then
            ((found_files++))
        else
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "Missing config files: ${missing_files[*]}" "$found_files" "files"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "All essential config files present" "$found_files" "files"
    fi
}

# Check YAML syntax
hc_check_yaml_syntax() {
    local check_name="yaml_syntax"
    local config_path="${1:-$HC_CONFIG_PATH}"
    
    if [[ ! -d "$config_path" ]]; then
        hc_record_result "$check_name" "$HC_STATUS_UNKNOWN" "Config directory not found" "" ""
        return
    fi
    
    local yaml_files
    mapfile -t yaml_files < <(find "$config_path" -name "*.yaml" -o -name "*.yml" 2>/dev/null | head -20)
    
    local invalid_files=()
    local total_files=${#yaml_files[@]}
    
    if [[ $total_files -eq 0 ]]; then
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "No YAML files found" "0" "files"
        return
    fi
    
    for yaml_file in "${yaml_files[@]}"; do
        if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" >/dev/null 2>&1; then
            if ! command -v yamllint >/dev/null 2>&1 || ! yamllint -q "$yaml_file" >/dev/null 2>&1; then
                invalid_files+=("$(basename "$yaml_file")")
            fi
        fi
    done
    
    if [[ ${#invalid_files[@]} -gt 0 ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Invalid YAML files: ${invalid_files[*]}" "${#invalid_files[@]}" "errors"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "All YAML files valid" "$total_files" "files"
    fi
}

# Check file permissions
hc_check_file_permissions() {
    local check_name="file_permissions"
    local config_path="${1:-$HC_CONFIG_PATH}"
    
    if [[ ! -d "$config_path" ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Config directory not found" "" ""
        return
    fi
    
    local permission_issues=()
    
    # Check if directory is readable
    if [[ ! -r "$config_path" ]]; then
        permission_issues+=("directory not readable")
    fi
    
    # Check if directory is writable
    if [[ ! -w "$config_path" ]]; then
        permission_issues+=("directory not writable")
    fi
    
    # Check key files
    local key_files=("configuration.yaml" "secrets.yaml")
    for file in "${key_files[@]}"; do
        local file_path="$config_path/$file"
        if [[ -f "$file_path" ]]; then
            if [[ ! -r "$file_path" ]]; then
                permission_issues+=("$file not readable")
            fi
            if [[ ! -w "$file_path" ]]; then
                permission_issues+=("$file not writable")
            fi
        fi
    done
    
    if [[ ${#permission_issues[@]} -gt 0 ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Permission issues: ${permission_issues[*]}" "${#permission_issues[@]}" "issues"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "File permissions OK" "0" "issues"
    fi
}

# Check Docker health (if running in Docker)
hc_check_docker_health() {
    local check_name="docker_health"
    
    if ! command -v docker >/dev/null 2>&1; then
        hc_record_result "$check_name" "$HC_STATUS_UNKNOWN" "Docker not available" "" ""
        return
    fi
    
    # Check if we're running in a container
    if [[ ! -f /.dockerenv ]] && ! grep -q "docker" /proc/1/cgroup 2>/dev/null; then
        hc_record_result "$check_name" "$HC_STATUS_OK" "Not running in Docker" "" ""
        return
    fi
    
    local container_id
    container_id=$(hostname)
    
    local container_status
    if container_status=$(docker inspect "$container_id" --format='{{.State.Status}}' 2>/dev/null); then
        if [[ "$container_status" == "running" ]]; then
            hc_record_result "$check_name" "$HC_STATUS_OK" "Container healthy" "" ""
        else
            hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "Container status: $container_status" "" ""
        fi
    else
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "Cannot check container status" "" ""
    fi
}

# Check network connectivity
hc_check_network_connectivity() {
    local check_name="network_connectivity"
    
    local targets=("8.8.8.8" "1.1.1.1")
    local reachable_targets=0
    
    for target in "${targets[@]}"; do
        if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
            ((reachable_targets++))
        fi
    done
    
    if [[ $reachable_targets -eq 0 ]]; then
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "No network connectivity" "$reachable_targets" "targets"
    elif [[ $reachable_targets -lt ${#targets[@]} ]]; then
        hc_record_result "$check_name" "$HC_STATUS_WARNING" "Limited network connectivity" "$reachable_targets" "targets"
    else
        hc_record_result "$check_name" "$HC_STATUS_OK" "Network connectivity OK" "$reachable_targets" "targets"
    fi
}

# Check MCP server response
hc_check_mcp_response() {
    local check_name="mcp_response"
    
    # This is a placeholder - would need to implement actual MCP protocol check
    # For now, check if the process is responding to signals
    if pgrep -f "server-filesystem" > /dev/null; then
        local pid=$(pgrep -f "server-filesystem")
        
        # Test if process is responding (send signal 0)
        if kill -0 "$pid" 2>/dev/null; then
            hc_record_result "$check_name" "$HC_STATUS_OK" "MCP server responding" "" ""
        else
            hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "MCP server not responding" "" ""
        fi
    else
        hc_record_result "$check_name" "$HC_STATUS_CRITICAL" "MCP server not running" "" ""
    fi
}

# =============================================================================
# Health Check Execution
# =============================================================================

# Run all health checks
hc_run_all_checks() {
    local config_path="${1:-$HC_CONFIG_PATH}"
    
    log_info "Running comprehensive health checks..."
    hc_init
    
    # Core system checks
    hc_check_mcp_process
    hc_check_disk_space "$config_path"
    hc_check_memory_usage
    hc_check_cpu_usage
    
    # Configuration checks
    hc_check_config_files "$config_path"
    hc_check_yaml_syntax "$config_path"
    hc_check_file_permissions "$config_path"
    
    # Infrastructure checks
    hc_check_docker_health
    hc_check_network_connectivity
    hc_check_mcp_response
    
    # Calculate overall status
    hc_calculate_overall_status
    
    log_info "Health checks completed: ${HC_RESULTS["overall"]}"
}

# Run specific health check
hc_run_check() {
    local check_name="$1"
    local config_path="${2:-$HC_CONFIG_PATH}"
    
    hc_init
    
    case "$check_name" in
        "mcp_process")
            hc_check_mcp_process
            ;;
        "disk_space")
            hc_check_disk_space "$config_path"
            ;;
        "memory_usage")
            hc_check_memory_usage
            ;;
        "cpu_usage")
            hc_check_cpu_usage
            ;;
        "config_files")
            hc_check_config_files "$config_path"
            ;;
        "yaml_syntax")
            hc_check_yaml_syntax "$config_path"
            ;;
        "file_permissions")
            hc_check_file_permissions "$config_path"
            ;;
        "docker_health")
            hc_check_docker_health
            ;;
        "network_connectivity")
            hc_check_network_connectivity
            ;;
        "mcp_response")
            hc_check_mcp_response
            ;;
        *)
            echo "Unknown health check: $check_name"
            exit 1
            ;;
    esac
    
    hc_calculate_overall_status
}

# =============================================================================
# Output Formatting
# =============================================================================

# Format health check results for human reading
hc_format_human() {
    echo "Health Check Report"
    echo "===================="
    echo "Overall Status: ${HC_RESULTS["overall"]}"
    echo "Timestamp: $(date -d "@${HC_RESULTS["timestamp"]}" 2>/dev/null || date -r "${HC_RESULTS["timestamp"]}" 2>/dev/null || echo "${HC_RESULTS["timestamp"]}")"
    echo "Total Checks: ${HC_RESULTS["checks_total"]}"
    echo "Passed: ${HC_RESULTS["checks_passed"]}"
    echo "Warnings: ${HC_RESULTS["checks_warnings"]}"
    echo "Critical: ${HC_RESULTS["checks_critical"]}"
    echo ""
    
    # Get all check names
    local check_names=()
    for key in "${!HC_RESULTS[@]}"; do
        if [[ "$key" =~ ^(.+)_status$ ]]; then
            check_names+=("${BASH_REMATCH[1]}")
        fi
    done
    
    # Sort check names
    IFS=$'\n' check_names=($(sort <<<"${check_names[*]}"))
    unset IFS
    
    # Display results for each check
    for check in "${check_names[@]}"; do
        local status="${HC_RESULTS["${check}_status"]:-}"
        local message="${HC_RESULTS["${check}_message"]:-}"
        local value="${HC_RESULTS["${check}_value"]:-}"
        local unit="${HC_RESULTS["${check}_unit"]:-}"
        
        if [[ -n "$status" ]]; then
            local status_symbol
            case "$status" in
                "$HC_STATUS_OK") status_symbol="✓" ;;
                "$HC_STATUS_WARNING") status_symbol="⚠" ;;
                "$HC_STATUS_CRITICAL") status_symbol="✗" ;;
                *) status_symbol="?" ;;
            esac
            
            printf "%s %-20s %s" "$status_symbol" "$check:" "$message"
            if [[ -n "$value" && -n "$unit" ]]; then
                printf " (%s%s)" "$value" "$unit"
            fi
            echo ""
        fi
    done
}

# Format health check results as JSON
hc_format_json() {
    echo "{"
    echo "  \"overall_status\": \"${HC_RESULTS["overall"]}\","
    echo "  \"timestamp\": ${HC_RESULTS["timestamp"]},"
    echo "  \"checks_total\": ${HC_RESULTS["checks_total"]},"
    echo "  \"checks_passed\": ${HC_RESULTS["checks_passed"]},"
    echo "  \"checks_warnings\": ${HC_RESULTS["checks_warnings"]},"
    echo "  \"checks_critical\": ${HC_RESULTS["checks_critical"]},"
    echo "  \"checks\": {"
    
    local first=true
    local check_names=()
    for key in "${!HC_RESULTS[@]}"; do
        if [[ "$key" =~ ^(.+)_status$ ]]; then
            check_names+=("${BASH_REMATCH[1]}")
        fi
    done
    
    IFS=$'\n' check_names=($(sort <<<"${check_names[*]}"))
    unset IFS
    
    for check in "${check_names[@]}"; do
        if [[ "$first" == "false" ]]; then
            echo ","
        fi
        first=false
        
        local status="${HC_RESULTS["${check}_status"]:-}"
        local message="${HC_RESULTS["${check}_message"]:-}"
        local value="${HC_RESULTS["${check}_value"]:-}"
        local unit="${HC_RESULTS["${check}_unit"]:-}"
        
        echo -n "    \"$check\": {"
        echo -n "\"status\": \"$status\", \"message\": \"$message\""
        if [[ -n "$value" ]]; then
            echo -n ", \"value\": \"$value\""
        fi
        if [[ -n "$unit" ]]; then
            echo -n ", \"unit\": \"$unit\""
        fi
        echo -n "}"
    done
    
    echo ""
    echo "  }"
    echo "}"
}

# Format health check results for Prometheus
hc_format_prometheus() {
    echo "# HELP mcp_health_check_status Health check status (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)"
    echo "# TYPE mcp_health_check_status gauge"
    
    local check_names=()
    for key in "${!HC_RESULTS[@]}"; do
        if [[ "$key" =~ ^(.+)_status$ ]]; then
            check_names+=("${BASH_REMATCH[1]}")
        fi
    done
    
    for check in "${check_names[@]}"; do
        local status="${HC_RESULTS["${check}_status"]:-}"
        local value="${HC_RESULTS["${check}_value"]:-}"
        
        local status_code
        case "$status" in
            "$HC_STATUS_OK") status_code=0 ;;
            "$HC_STATUS_WARNING") status_code=1 ;;
            "$HC_STATUS_CRITICAL") status_code=2 ;;
            *) status_code=3 ;;
        esac
        
        echo "mcp_health_check_status{check=\"$check\"} $status_code"
        
        if [[ -n "$value" && "$value" =~ ^[0-9]+$ ]]; then
            echo "mcp_health_check_value{check=\"$check\"} $value"
        fi
    done
    
    echo "mcp_health_overall_status ${HC_RESULTS["overall"]}"
    echo "mcp_health_checks_total ${HC_RESULTS["checks_total"]}"
    echo "mcp_health_checks_passed ${HC_RESULTS["checks_passed"]}"
    echo "mcp_health_checks_warnings ${HC_RESULTS["checks_warnings"]}"
    echo "mcp_health_checks_critical ${HC_RESULTS["checks_critical"]}"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local action="${1:-all}"
    local config_path="${2:-$HC_CONFIG_PATH}"
    local output_format="${3:-$HC_OUTPUT_FORMAT}"
    
    case "$action" in
        "all")
            hc_run_all_checks "$config_path"
            ;;
        "check")
            if [[ -n "${2:-}" ]]; then
                hc_run_check "$2" "$config_path"
            else
                echo "Usage: $0 check <check_name> [config_path] [format]"
                exit 1
            fi
            ;;
        "list")
            echo "Available health checks:"
            echo "  mcp_process      - Check MCP server process"
            echo "  disk_space       - Check disk space usage"
            echo "  memory_usage     - Check memory usage"
            echo "  cpu_usage        - Check CPU usage"
            echo "  config_files     - Check configuration files"
            echo "  yaml_syntax      - Check YAML syntax"
            echo "  file_permissions - Check file permissions"
            echo "  docker_health    - Check Docker container health"
            echo "  network_connectivity - Check network connectivity"
            echo "  mcp_response     - Check MCP server response"
            exit 0
            ;;
        "test")
            echo "Running health check system test..."
            hc_run_all_checks "$config_path"
            ;;
        *)
            echo "Usage: $0 {all|check|list|test} [args...]"
            echo ""
            echo "Commands:"
            echo "  all [config_path] [format]           - Run all health checks"
            echo "  check <name> [config_path] [format]  - Run specific health check"
            echo "  list                                 - List available health checks"
            echo "  test                                 - Run health check system test"
            echo ""
            echo "Output formats: human (default), json, prometheus"
            exit 1
            ;;
    esac
    
    # Format and display output
    case "$output_format" in
        "json")
            hc_format_json
            ;;
        "prometheus")
            hc_format_prometheus
            ;;
        "human"|*)
            hc_format_human
            ;;
    esac
    
    # Exit with appropriate code based on overall status
    case "${HC_RESULTS["overall"]}" in
        "$HC_STATUS_OK")
            exit 0
            ;;
        "$HC_STATUS_WARNING")
            exit 1
            ;;
        "$HC_STATUS_CRITICAL")
            exit 2
            ;;
        *)
            exit 3
            ;;
    esac
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f hc_run_all_checks hc_run_check hc_format_human hc_format_json hc_format_prometheus
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi