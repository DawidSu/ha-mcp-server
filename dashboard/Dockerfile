# Multi-stage build for React frontend and Node.js API
FROM node:18-alpine AS frontend-builder

# Build frontend
WORKDIR /app/frontend
COPY package*.json ./
RUN npm ci --only=production
COPY src/ ./src/
COPY public/ ./public/
COPY tsconfig.json tailwind.config.js postcss.config.js ./
RUN npm run build

# API stage
FROM node:18-alpine AS api-builder

# Build API
WORKDIR /app/api
COPY api/package*.json ./
RUN npm ci --only=production

# Production stage
FROM node:18-alpine

# Install required system packages
RUN apk add --no-cache \
    bash \
    curl \
    procps \
    && rm -rf /var/cache/apk/*

# Create app user
RUN addgroup -g 1000 dashboard && \
    adduser -D -s /bin/bash -u 1000 -G dashboard dashboard

# Create app directory
WORKDIR /app

# Copy API dependencies and code
COPY --from=api-builder /app/api/node_modules ./api/node_modules
COPY api/ ./api/

# Copy built frontend
COPY --from=frontend-builder /app/frontend/build ./frontend/build

# Copy startup script
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Create necessary directories
RUN mkdir -p /var/log /tmp/dashboard-cache && \
    chown -R dashboard:dashboard /app /var/log /tmp/dashboard-cache

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Switch to non-root user
USER dashboard

# Expose ports
EXPOSE 3000 3001

# Start both API and frontend
CMD ["/app/start.sh"]