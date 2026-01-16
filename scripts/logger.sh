#!/bin/bash

# Structured logging functions for MCP Server
# Provides JSON-formatted logs for better monitoring

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_CRITICAL=4

# Default log level
CURRENT_LOG_LEVEL=${LOG_LEVEL:-1}

# Convert string log level to numeric
get_log_level_numeric() {
    case "$1" in
        debug|DEBUG) echo $LOG_LEVEL_DEBUG ;;
        info|INFO) echo $LOG_LEVEL_INFO ;;
        warning|WARNING|warn|WARN) echo $LOG_LEVEL_WARNING ;;
        error|ERROR) echo $LOG_LEVEL_ERROR ;;
        critical|CRITICAL) echo $LOG_LEVEL_CRITICAL ;;
        *) echo $LOG_LEVEL_INFO ;;
    esac
}

# Set current log level
if [ ! -z "$LOG_LEVEL" ]; then
    CURRENT_LOG_LEVEL=$(get_log_level_numeric "$LOG_LEVEL")
fi

# JSON escape function
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

# Structured logging function
log_structured() {
    local level=$1
    local message=$2
    local component=${3:-"mcp-server"}
    local extra_fields=${4:-""}
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local hostname=$(hostname)
    
    # Build JSON log entry
    local json_log="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"component\":\"$component\",\"hostname\":\"$hostname\",\"message\":\"$(json_escape "$message")\""
    
    # Add extra fields if provided
    if [ ! -z "$extra_fields" ]; then
        json_log="$json_log,$extra_fields"
    fi
    
    json_log="$json_log}"
    
    # Output to stderr for systemd/docker logging
    echo "$json_log" >&2
    
    # Also output human-readable to stdout if in TTY
    if [ -t 1 ]; then
        case "$level" in
            DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" ;;
            INFO) echo -e "${GREEN}[INFO]${NC} $message" ;;
            WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
            ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
            CRITICAL) echo -e "${RED}[CRITICAL]${NC} $message" ;;
        esac
    fi
}

# Convenience functions
log_debug() {
    [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ] && log_structured "DEBUG" "$1" "${2:-mcp-server}" "$3"
}

log_info() {
    [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ] && log_structured "INFO" "$1" "${2:-mcp-server}" "$3"
}

log_warning() {
    [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARNING ] && log_structured "WARNING" "$1" "${2:-mcp-server}" "$3"
}

log_error() {
    [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_ERROR ] && log_structured "ERROR" "$1" "${2:-mcp-server}" "$3"
}

log_critical() {
    [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_CRITICAL ] && log_structured "CRITICAL" "$1" "${2:-mcp-server}" "$3"
}

# Performance metrics logging
log_metric() {
    local metric_name=$1
    local metric_value=$2
    local metric_unit=${3:-""}
    local tags=${4:-""}
    
    local extra_fields="\"metric_name\":\"$metric_name\",\"metric_value\":$metric_value"
    
    if [ ! -z "$metric_unit" ]; then
        extra_fields="$extra_fields,\"metric_unit\":\"$metric_unit\""
    fi
    
    if [ ! -z "$tags" ]; then
        extra_fields="$extra_fields,$tags"
    fi
    
    log_structured "METRIC" "Performance metric: $metric_name=$metric_value$metric_unit" "metrics" "$extra_fields"
}

# Audit logging for security-relevant events
log_audit() {
    local action=$1
    local user=${2:-"system"}
    local resource=$3
    local result=${4:-"success"}
    
    local extra_fields="\"audit_action\":\"$action\",\"audit_user\":\"$user\",\"audit_result\":\"$result\""
    
    if [ ! -z "$resource" ]; then
        extra_fields="$extra_fields,\"audit_resource\":\"$(json_escape "$resource")\""
    fi
    
    log_structured "AUDIT" "Action: $action by $user on $resource - $result" "audit" "$extra_fields"
}

# Export functions for use in other scripts
export -f log_structured
export -f log_debug
export -f log_info
export -f log_warning
export -f log_error
export -f log_critical
export -f log_metric
export -f log_audit
export -f json_escape