#!/usr/bin/with-contenv bashio
set -e

# Get configuration from addon options with validation
CONFIG_PATH=$(bashio::config 'ha_config_path' || echo "/config")
LOG_LEVEL=$(bashio::config 'log_level' || echo "info")

# Validate log level
case "${LOG_LEVEL}" in
    debug|info|warning|error) ;;
    *) 
        bashio::log.warning "Invalid log level: ${LOG_LEVEL}, using 'info'"
        LOG_LEVEL="info"
        ;;
esac

# Log configuration
bashio::log.info "Starting Claude MCP Server..."
bashio::log.info "Home Assistant Config Path: ${CONFIG_PATH}"
bashio::log.info "Log Level: ${LOG_LEVEL}"

# Enhanced directory validation
if [ ! -d "${CONFIG_PATH}" ]; then
    bashio::log.error "Config directory not found: ${CONFIG_PATH}"
    bashio::log.error "Please ensure Home Assistant config is properly mounted"
    
    # Try to provide helpful debugging info
    bashio::log.info "Available directories:"
    ls -la /config/ 2>/dev/null || bashio::log.error "Cannot list /config directory"
    ls -la / 2>/dev/null | grep config || bashio::log.error "No config directories found"
    exit 1
fi

# Check read permissions
if [ ! -r "${CONFIG_PATH}" ]; then
    bashio::log.error "Config directory is not readable: ${CONFIG_PATH}"
    bashio::log.error "Permission issue detected. Current user: $(whoami)"
    ls -ld "${CONFIG_PATH}" || true
    exit 1
fi

# Set environment variables
export HA_CONFIG_PATH="${CONFIG_PATH}"
export LOG_LEVEL="${LOG_LEVEL}"

# Start the MCP filesystem server
bashio::log.info "Starting MCP Filesystem Server on port 3000..."

# List some key files to verify access
bashio::log.info "Verifying file access..."
if [ -f "${CONFIG_PATH}/configuration.yaml" ]; then
    bashio::log.info "✓ Found configuration.yaml"
else
    bashio::log.warning "⚠ configuration.yaml not found - this might be normal for new installations"
fi

if [ -d "${CONFIG_PATH}/automations" ] || [ -f "${CONFIG_PATH}/automations.yaml" ]; then
    bashio::log.info "✓ Found automations"
fi

if [ -d "${CONFIG_PATH}/scripts" ] || [ -f "${CONFIG_PATH}/scripts.yaml" ]; then
    bashio::log.info "✓ Found scripts"
fi

# Load security utilities if available
if [[ -f "/opt/scripts/security-utils.sh" ]]; then
    source "/opt/scripts/security-utils.sh"
    bashio::log.info "Security utilities loaded"
    
    # Validate configuration path
    if ! validate_config_path "${CONFIG_PATH}"; then
        bashio::log.error "Invalid configuration path: ${CONFIG_PATH}"
        exit 1
    fi
fi

# Initialize caching if available
if [[ -f "/opt/scripts/cache-manager.sh" ]]; then
    source "/opt/scripts/cache-manager.sh"
    cache_init
    bashio::log.info "Cache system initialized"
fi

# Initialize circuit breakers if available
if [[ -f "/opt/scripts/circuit-breaker.sh" ]]; then
    source "/opt/scripts/circuit-breaker.sh"
    cb_init "mcp_server"
    bashio::log.info "Circuit breaker system initialized"
fi

# Function to handle signals for graceful shutdown
cleanup_on_exit() {
    bashio::log.info "Received shutdown signal, stopping MCP server gracefully..."
    
    # Stop any background processes
    pkill -f "cache_daemon" 2>/dev/null || true
    pkill -f "monitor.sh" 2>/dev/null || true
    
    # Save cache state
    if command -v cache_save_stats >/dev/null 2>&1; then
        cache_save_stats
    fi
    
    exit 0
}

trap cleanup_on_exit SIGTERM SIGINT

# Start background monitoring if available
if [[ -f "/opt/scripts/monitor.sh" ]]; then
    bashio::log.info "Starting background monitoring"
    /opt/scripts/monitor.sh &
fi

# Run initial health check
if [[ -f "/opt/scripts/health-check.sh" ]]; then
    bashio::log.info "Running initial health check..."
    if /opt/scripts/health-check.sh all >/dev/null 2>&1; then
        bashio::log.info "✓ Initial health check passed"
    else
        bashio::log.warning "⚠ Initial health check had warnings - continuing anyway"
    fi
fi

# Start the MCP filesystem server with monitoring
bashio::log.info "Starting MCP Filesystem Server on port 3000..."
bashio::log.info "Claude can now access your Home Assistant configuration!"
bashio::log.info "Press Ctrl+C to stop the server"

# Start server with circuit breaker protection
if command -v cb_execute >/dev/null 2>&1; then
    # Start with circuit breaker protection
    if ! cb_execute "mcp_server" "npx -y @modelcontextprotocol/server-filesystem '${CONFIG_PATH}'"; then
        bashio::log.error "MCP server failed to start or crashed (circuit breaker)"
        exit 1
    fi
else
    # Fallback without circuit breaker
    if ! exec npx -y @modelcontextprotocol/server-filesystem "${CONFIG_PATH}"; then
        bashio::log.error "MCP server failed to start or crashed"
        bashio::log.error "Check the logs above for more details"
        exit 1
    fi
fi