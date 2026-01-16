#!/bin/bash

# Monitoring script for MCP Server
# Collects and reports metrics about the server operation

set -e

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logger.sh"

# Configuration
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}  # Check every 60 seconds
CONTAINER_NAME="homeassistant-mcp-server"
METRICS_FILE="/tmp/mcp-metrics.json"

# Initialize metrics
TOTAL_REQUESTS=0
TOTAL_ERRORS=0
START_TIME=$(date +%s)

# Function to collect Docker stats
collect_docker_stats() {
    # Check if docker command is available
    if ! command -v docker >/dev/null 2>&1; then
        log_debug "Docker command not available, skipping Docker stats collection"
        return 0
    fi
    
    if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        local stats=$(docker stats --no-stream --format "json" "$CONTAINER_NAME" 2>/dev/null)
        
        if [ ! -z "$stats" ]; then
            local cpu_percent=$(echo "$stats" | jq -r '.CPUPerc' | sed 's/%//')
            local mem_usage=$(echo "$stats" | jq -r '.MemUsage' | cut -d'/' -f1 | sed 's/[^0-9.]//g')
            local mem_limit=$(echo "$stats" | jq -r '.MemUsage' | cut -d'/' -f2 | sed 's/[^0-9.]//g')
            
            log_metric "cpu_usage" "$cpu_percent" "percent" "\"container\":\"$CONTAINER_NAME\""
            log_metric "memory_usage" "$mem_usage" "MiB" "\"container\":\"$CONTAINER_NAME\""
            log_metric "memory_limit" "$mem_limit" "MiB" "\"container\":\"$CONTAINER_NAME\""
            
            # Check if memory usage is high
            if (( $(echo "$mem_usage > $mem_limit * 0.8" | bc -l) )); then
                log_warning "High memory usage detected: ${mem_usage}MiB / ${mem_limit}MiB" "monitor"
            fi
        fi
    else
        log_error "Container $CONTAINER_NAME is not running" "monitor"
        return 1
    fi
}

# Function to check file system usage
check_filesystem_usage() {
    local config_path=${HA_CONFIG_PATH:-/config}
    
    if [ -d "$config_path" ]; then
        local usage=$(df -h "$config_path" | awk 'NR==2 {print $5}' | sed 's/%//')
        local available=$(df -h "$config_path" | awk 'NR==2 {print $4}')
        
        log_metric "disk_usage" "$usage" "percent" "\"path\":\"$config_path\""
        log_debug "Disk space available: $available" "monitor"
        
        # Alert if disk usage is high
        if [ "$usage" -gt 90 ]; then
            log_critical "Critical: Disk usage at ${usage}% for $config_path" "monitor"
        elif [ "$usage" -gt 80 ]; then
            log_warning "Warning: Disk usage at ${usage}% for $config_path" "monitor"
        fi
    fi
}

# Function to check process health
check_process_health() {
    # Check if MCP server process is running
    if pgrep -f "server-filesystem" > /dev/null; then
        log_debug "MCP server process is running" "monitor"
        log_metric "process_status" "1" "" "\"process\":\"mcp-server\""
        
        # Get process info
        local pid=$(pgrep -f "server-filesystem" | head -1)
        if [ ! -z "$pid" ]; then
            # Get process CPU and memory usage
            local process_stats=$(ps -o pid,vsz,rss,pcpu,pmem,etime -p "$pid" | tail -1)
            local cpu_usage=$(echo "$process_stats" | awk '{print $4}')
            local mem_percent=$(echo "$process_stats" | awk '{print $5}')
            local uptime=$(echo "$process_stats" | awk '{print $6}')
            
            log_metric "process_cpu" "$cpu_usage" "percent" "\"pid\":\"$pid\""
            log_metric "process_memory" "$mem_percent" "percent" "\"pid\":\"$pid\""
            log_info "MCP server uptime: $uptime" "monitor"
        fi
    else
        log_error "MCP server process is not running" "monitor"
        log_metric "process_status" "0" "" "\"process\":\"mcp-server\""
        return 1
    fi
}

# Function to analyze logs for errors
analyze_logs() {
    local log_file="/var/log/mcp-server.log"
    
    if [ -f "$log_file" ]; then
        # Count errors in last 5 minutes
        local five_min_ago=$(date -d '5 minutes ago' '+%Y-%m-%d %H:%M:%S')
        local error_count=$(grep -c "ERROR\|CRITICAL" "$log_file" 2>/dev/null || echo 0)
        
        if [ "$error_count" -gt 0 ]; then
            log_warning "Found $error_count errors in logs" "monitor"
            log_metric "error_count" "$error_count" "errors" "\"timeframe\":\"5min\""
            
            # Get last error
            local last_error=$(grep "ERROR\|CRITICAL" "$log_file" | tail -1)
            if [ ! -z "$last_error" ]; then
                log_debug "Last error: $last_error" "monitor"
            fi
        fi
    fi
}

# Function to check connectivity
check_connectivity() {
    local port=3000
    
    # Check if port is listening
    if netstat -tuln | grep -q ":$port "; then
        log_debug "Port $port is listening" "monitor"
        log_metric "port_status" "1" "" "\"port\":\"$port\""
        
        # Try to connect to the port
        if timeout 2 bash -c "echo > /dev/tcp/localhost/$port" 2>/dev/null; then
            log_debug "Successfully connected to port $port" "monitor"
            log_metric "connectivity" "1" "" "\"port\":\"$port\""
        else
            log_warning "Could not connect to port $port" "monitor"
            log_metric "connectivity" "0" "" "\"port\":\"$port\""
        fi
    else
        log_error "Port $port is not listening" "monitor"
        log_metric "port_status" "0" "" "\"port\":\"$port\""
    fi
}

# Function to save metrics to file
save_metrics() {
    local current_time=$(date +%s)
    local uptime=$((current_time - START_TIME))
    
    cat > "$METRICS_FILE" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")",
    "uptime_seconds": $uptime,
    "total_requests": $TOTAL_REQUESTS,
    "total_errors": $TOTAL_ERRORS,
    "status": "running"
}
EOF
    
    log_debug "Metrics saved to $METRICS_FILE" "monitor"
}

# Main monitoring loop
main() {
    log_info "Starting MCP Server monitoring" "monitor"
    log_info "Monitor interval: ${MONITOR_INTERVAL}s" "monitor"
    
    while true; do
        log_debug "Running monitoring checks..." "monitor"
        
        # Run all checks
        collect_docker_stats || true
        check_filesystem_usage || true
        check_process_health || true
        analyze_logs || true
        check_connectivity || true
        save_metrics || true
        
        # Sleep until next check
        sleep "$MONITOR_INTERVAL"
    done
}

# Handle signals
trap 'log_info "Monitoring stopped" "monitor"; exit 0' SIGTERM SIGINT

# Run main function
main "$@"