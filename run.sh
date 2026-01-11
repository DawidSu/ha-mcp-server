#!/usr/bin/with-contenv bashio

# Get configuration from addon options
CONFIG_PATH=$(bashio::config 'ha_config_path')
LOG_LEVEL=$(bashio::config 'log_level')

# Set defaults
CONFIG_PATH=${CONFIG_PATH:-"/config"}
LOG_LEVEL=${LOG_LEVEL:-"info"}

# Log configuration
bashio::log.info "Starting Claude MCP Server..."
bashio::log.info "Home Assistant Config Path: ${CONFIG_PATH}"
bashio::log.info "Log Level: ${LOG_LEVEL}"

# Check if config directory exists
if [ ! -d "${CONFIG_PATH}" ]; then
    bashio::log.error "Config directory not found: ${CONFIG_PATH}"
    bashio::log.error "Please ensure Home Assistant config is properly mounted"
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

# Start the MCP filesystem server
bashio::log.info "Starting MCP Filesystem Server on port 3000..."
bashio::log.info "Claude can now access your Home Assistant configuration!"

exec npx -y @modelcontextprotocol/server-filesystem "${CONFIG_PATH}"