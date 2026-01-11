FROM node:20-alpine

# Install necessary packages
RUN apk add --no-cache git

# Create app directory
WORKDIR /app

# Install MCP server for filesystem access
RUN npm install -g @modelcontextprotocol/server-filesystem

# Create a startup script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Expose MCP server port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('net').connect(3000, 'localhost')" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
