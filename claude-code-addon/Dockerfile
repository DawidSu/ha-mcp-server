ARG BUILD_FROM
FROM $BUILD_FROM

# Install Node.js, npm and dependencies
RUN apk add --no-cache \
        nodejs \
        npm \
        bash \
        python3 \
        py3-yaml \
        curl \
        git \
    && rm -rf /var/cache/apk/*

# Create app user
RUN addgroup -g 1000 appuser && \
    adduser -D -s /bin/bash -u 1000 -G appuser appuser

# Create app directory
WORKDIR /app

# Copy package.json and install dependencies
COPY src/package.json /app/package.json
RUN npm install --production && \
    chown -R appuser:appuser /app

# Copy application files
COPY src/ /app/
COPY run.sh /run.sh

# Set permissions
RUN chmod +x /run.sh && \
    chown -R appuser:appuser /app

# Labels
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

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

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Switch to app user
USER appuser

# Expose port
EXPOSE 8080

CMD [ "/run.sh" ]