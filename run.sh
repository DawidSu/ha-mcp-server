#!/usr/bin/with-contenv bashio
set -e

# Get configuration from addon options with validation
CONFIG_PATH=$(bashio::config 'ha_config_path' || echo "/config")
LOG_LEVEL=$(bashio::config 'log_level' || echo "info")

# Export log level for scripts
export LOG_LEVEL

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
    if source "/opt/scripts/security-utils.sh" 2>/dev/null; then
        bashio::log.info "Security utilities loaded"
        
        # Validate configuration path if function exists
        if command -v validate_config_path >/dev/null 2>&1; then
            if ! validate_config_path "${CONFIG_PATH}" 2>/dev/null; then
                bashio::log.warning "Configuration path validation failed: ${CONFIG_PATH}"
                # Don't exit - continue anyway
            fi
        fi
    else
        bashio::log.warning "Failed to load security utilities - continuing without them"
    fi
fi

# Initialize caching if available
if [[ -f "/opt/scripts/cache-manager.sh" ]]; then
    if source "/opt/scripts/cache-manager.sh" 2>/dev/null; then
        if command -v cache_init >/dev/null 2>&1; then
            if cache_init 2>/dev/null; then
                bashio::log.info "Cache system initialized"
            else
                bashio::log.warning "Cache initialization failed - continuing without cache"
            fi
        fi
    else
        bashio::log.warning "Failed to load cache utilities - continuing without them"
    fi
fi

# Initialize circuit breakers if available
if [[ -f "/opt/scripts/circuit-breaker.sh" ]]; then
    if source "/opt/scripts/circuit-breaker.sh" 2>/dev/null; then
        if command -v cb_init >/dev/null 2>&1; then
            if cb_init "mcp_server" 2>/dev/null; then
                bashio::log.info "Circuit breaker system initialized"
            else
                bashio::log.warning "Circuit breaker initialization failed - continuing without it"
            fi
        fi
    else
        bashio::log.warning "Failed to load circuit breaker utilities - continuing without them"
    fi
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
    # Start monitoring in background, suppress errors if Docker not available
    (/opt/scripts/monitor.sh 2>/dev/null) &
fi

# Start Dashboard API on port 3001 if files exist
if [[ -f "/dashboard/api/server.js" ]]; then
    bashio::log.info "Starting Dashboard API on port 3001..."
    cd /dashboard/api || {
        bashio::log.error "Failed to change to dashboard directory"
        exit 1
    }
    
    # Test node and dependencies first
    if ! node --version >/dev/null 2>&1; then
        bashio::log.error "Node.js not available"
        exit 1
    fi
    
    if ! ls node_modules >/dev/null 2>&1; then
        bashio::log.warning "No node_modules found, dashboard may not work"
    fi
    
    nohup node server.js >/tmp/dashboard.log 2>&1 &
    DASHBOARD_PID=$!
    bashio::log.info "Dashboard API started with PID: $DASHBOARD_PID"
    
    # Give dashboard time to start
    sleep 2
    
    # Check if still running
    if ! kill -0 $DASHBOARD_PID 2>/dev/null; then
        bashio::log.error "Dashboard API failed to start"
        bashio::log.error "Dashboard logs:"
        cat /tmp/dashboard.log 2>/dev/null || bashio::log.error "No dashboard logs"
    fi
    
    cd / || true
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

# Function to keep container running
keep_alive() {
    bashio::log.info "MCP server is running in background - keeping container alive"
    while true; do
        sleep 60
        # Check if MCP process is still running
        if ! pgrep -f "tcp-wrapper.js" >/dev/null; then
            bashio::log.error "MCP server process died - restarting TCP wrapper"
            # Kill any remaining processes on port 3000
            pkill -f "tcp-wrapper.js" 2>/dev/null || true
            sleep 2
            # Restart TCP wrapper
            MCP_PORT=3000 nohup node /opt/scripts/tcp-wrapper.js "${CONFIG_PATH}" >/tmp/mcp-server.log 2>&1 &
            MCP_PID=$!
            bashio::log.info "TCP wrapper restarted with PID: $MCP_PID"
        fi
    done
}

# Test NPX and MCP package first
bashio::log.info "Testing NPX and MCP package..."
if ! which npx >/dev/null 2>&1; then
    bashio::log.error "NPX not found in PATH"
    exit 1
fi

if ! npm list -g @modelcontextprotocol/server-filesystem >/dev/null 2>&1; then
    bashio::log.error "MCP server package not found"
    npm list -g 2>&1 | head -10
    exit 1
fi

# Copy TCP wrapper to correct location
if [ ! -f "/opt/scripts/tcp-wrapper.js" ]; then
    cp /tcp-wrapper.js /opt/scripts/tcp-wrapper.js 2>/dev/null || true
fi

# Start MCP server via TCP wrapper on port 3000
bashio::log.info "Starting MCP TCP wrapper on port 3000..."
bashio::log.info "Command: node /opt/scripts/tcp-wrapper.js ${CONFIG_PATH}"

# Use nohup to properly daemonize with TCP wrapper
MCP_PORT=3000 nohup node /opt/scripts/tcp-wrapper.js "${CONFIG_PATH}" >/tmp/mcp-server.log 2>&1 &
MCP_PID=$!

bashio::log.info "MCP server started with PID: $MCP_PID"

# Give server time to start and check logs
sleep 5

# Check if process is still running and port is listening
if kill -0 $MCP_PID 2>/dev/null && netstat -ln 2>/dev/null | grep -q ":3000 "; then
    bashio::log.info "✓ MCP TCP server is running and listening on port 3000"
    bashio::log.info "Server logs:"
    tail -n 10 /tmp/mcp-server.log 2>/dev/null || bashio::log.warning "No logs available yet"
    
    # Simple keep-alive loop without restart logic
    bashio::log.info "MCP server ready - keeping container alive"
    while kill -0 $MCP_PID 2>/dev/null; do
        sleep 60
    done
    
    bashio::log.error "MCP server process died"
    exit 1
else
    bashio::log.error "✗ MCP server failed to start or port not listening"
    bashio::log.error "Server logs:"
    cat /tmp/mcp-server.log 2>/dev/null || bashio::log.error "No logs available"
    
    # Check what's using port 3000
    bashio::log.info "Checking port 3000 usage:"
    netstat -tlnp 2>/dev/null | grep ":3000 " || bashio::log.info "Port 3000 not in use"
    exit 1
fi