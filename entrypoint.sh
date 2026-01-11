#!/bin/sh

# Entrypoint script for Home Assistant MCP Server

echo "Starting Home Assistant MCP Server..."
echo "Monitoring directory: ${HA_CONFIG_PATH:-/config}"

# Start the MCP filesystem server
# This exposes the Home Assistant config directory to Claude
exec npx -y @modelcontextprotocol/server-filesystem "${HA_CONFIG_PATH:-/config}"
