#!/usr/bin/with-contenv bashio
set -euo pipefail

# Get configuration from addon options
API_KEY=$(bashio::config 'anthropic_api_key')
MODEL=$(bashio::config 'model')
MAX_TOKENS=$(bashio::config 'max_tokens')
AUTO_CONNECT_MCP=$(bashio::config 'auto_connect_mcp')
MCP_HOST=$(bashio::config 'mcp_server_host')
MCP_PORT=$(bashio::config 'mcp_server_port')
LOG_LEVEL=$(bashio::config 'log_level')

# Validate configuration
if [ -z "$API_KEY" ]; then
    bashio::log.warning "Kein Anthropic API Key konfiguriert!"
    bashio::log.warning "Bitte API Key in den Addon-Einstellungen hinzufügen."
    bashio::log.warning "Claude Funktionalität ist deaktiviert bis API Key gesetzt ist."
fi

# Export environment variables for Node.js app
export ANTHROPIC_API_KEY="$API_KEY"
export ADDON_OPTIONS=$(bashio::addon.options)
export NODE_ENV=production
export PORT=8080

# Log configuration (without exposing API key)
bashio::log.info "Starting Claude Code Addon..."
bashio::log.info "Model: $MODEL"
bashio::log.info "Max Tokens: $MAX_TOKENS"
bashio::log.info "MCP Auto Connect: $AUTO_CONNECT_MCP"
bashio::log.info "MCP Server: $MCP_HOST:$MCP_PORT"
bashio::log.info "Log Level: $LOG_LEVEL"

# Validate API key format (without logging it)
if [ -n "$API_KEY" ]; then
    if echo "$API_KEY" | grep -q "^sk-ant-"; then
        bashio::log.info "✅ API Key format appears valid"
    else
        bashio::log.warning "⚠️ API Key format may be invalid (should start with 'sk-ant-')"
    fi
fi

# Check if MCP server is reachable if auto-connect is enabled
if [ "$AUTO_CONNECT_MCP" = "true" ]; then
    bashio::log.info "Testing MCP server connection..."
    if timeout 5 bash -c "</dev/tcp/$MCP_HOST/$MCP_PORT" 2>/dev/null; then
        bashio::log.info "✅ MCP server is reachable at $MCP_HOST:$MCP_PORT"
    else
        bashio::log.warning "⚠️ MCP server not reachable at $MCP_HOST:$MCP_PORT"
        bashio::log.warning "Make sure the Claude MCP Server addon is running"
    fi
fi

# Change to app directory
cd /app

# Check if dependencies are installed
if [ ! -d "node_modules" ]; then
    bashio::log.error "Node.js dependencies not found!"
    bashio::log.error "Container may not have built correctly"
    exit 1
fi

# Verify Node.js
if ! node --version >/dev/null 2>&1; then
    bashio::log.error "Node.js not available!"
    exit 1
fi

bashio::log.info "Node.js version: $(node --version)"

# Set up signal handling for graceful shutdown
cleanup() {
    bashio::log.info "Shutting down Claude Code Addon..."
    # Kill any background processes
    pkill -f "node.*server.js" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start the application
bashio::log.info "Starting Claude Code web interface on port 8080..."
bashio::log.info "Access via Home Assistant Ingress"

# Run the Node.js server
exec node server.js