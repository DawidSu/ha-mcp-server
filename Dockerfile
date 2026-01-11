ARG BUILD_FROM
FROM $BUILD_FROM

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Node.js and npm
RUN \
    apk add --no-cache \
        nodejs \
        npm \
        git \
    && npm install -g @modelcontextprotocol/server-filesystem

# Copy run script
COPY run.sh /
RUN chmod a+x /run.sh

# Expose port
EXPOSE 3000

CMD [ "/run.sh" ]
