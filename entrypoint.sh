#!/bin/sh
set -e

# Entrypoint script for Home Assistant MCP Server

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

# Validate configuration
CONFIG_PATH="${HA_CONFIG_PATH:-/config}"

log "Starting Home Assistant MCP Server..."
log "Monitoring directory: ${CONFIG_PATH}"

# Check if config directory exists and is readable
if [ ! -d "${CONFIG_PATH}" ]; then
    error "Config directory does not exist: ${CONFIG_PATH}"
fi

if [ ! -r "${CONFIG_PATH}" ]; then
    error "Config directory is not readable: ${CONFIG_PATH}"
fi

# Verify npx is available
if ! command -v npx >/dev/null 2>&1; then
    error "npx is not installed or not in PATH"
fi

# Check if the MCP server package is available
log "Checking MCP server package..."
if ! npx -y @modelcontextprotocol/server-filesystem --version >/dev/null 2>&1; then
    error "Failed to load @modelcontextprotocol/server-filesystem package"
fi

log "All checks passed, starting MCP filesystem server..."

# Start the MCP filesystem server with error handling
exec npx -y @modelcontextprotocol/server-filesystem "${CONFIG_PATH}" || error "MCP server failed to start"
