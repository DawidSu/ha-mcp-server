# Build arguments
ARG BUILD_FROM

# Production stage
FROM $BUILD_FROM

# Install minimal dependencies
RUN apk add --no-cache \
        nodejs \
        npm \
        bash \
        python3 \
        py3-yaml \
        curl \
        procps \
    && rm -rf /var/cache/apk/*

# Install Node.js and NPM, then install MCP server directly
RUN npm install -g @modelcontextprotocol/server-filesystem

# Copy scripts and configuration
COPY scripts/ /opt/scripts/
COPY run.sh /run.sh
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /run.sh /entrypoint.sh /opt/scripts/*.sh

# Create non-root user for security
RUN addgroup -g 1000 mcpuser && \
    adduser -D -s /bin/bash -u 1000 -G mcpuser mcpuser

# Create necessary directories
RUN mkdir -p /var/log /tmp/mcp-cache && \
    chown -R mcpuser:mcpuser /var/log /tmp/mcp-cache

# Build arugments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="DawidSu" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Home Assistant Community Add-ons" \
    org.opencontainers.image.authors="DawidSu" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/DawidSu/ha-mcp-server" \
    org.opencontainers.image.source="https://github.com/DawidSu/ha-mcp-server" \
    org.opencontainers.image.documentation="https://github.com/DawidSu/ha-mcp-server/blob/main/README.md" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

# Improved health check using our health check script
HEALTHCHECK --interval=30s --timeout=15s --start-period=10s --retries=3 \
  CMD /opt/scripts/health-check.sh check mcp_process || exit 1

# Switch to non-root user
USER mcpuser

# Set working directory
WORKDIR /opt/scripts

CMD [ "/run.sh" ]
