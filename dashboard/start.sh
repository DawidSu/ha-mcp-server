#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" >&2
}

# Configuration
API_PORT=${DASHBOARD_PORT:-3000}
FRONTEND_PORT=${FRONTEND_PORT:-3001}
NODE_ENV=${NODE_ENV:-production}

log "Starting HA MCP Dashboard..."
log "API Port: $API_PORT"
log "Frontend Port: $FRONTEND_PORT"
log "Environment: $NODE_ENV"

# Function to start API server
start_api() {
    log "Starting API server on port $API_PORT..."
    cd /app/api
    
    # Check if scripts directory is available
    if [ ! -d "/opt/scripts" ]; then
        warn "Scripts directory not found. Some API endpoints may not work properly."
    fi
    
    # Start the API server
    exec node server.js &
    API_PID=$!
    
    log "API server started with PID: $API_PID"
    return $API_PID
}

# Function to start frontend server  
start_frontend() {
    log "Starting frontend server on port $FRONTEND_PORT..."
    
    # Install serve if not already installed
    npm install -g serve
    
    # Start serving the built frontend
    cd /app
    exec serve -s frontend/build -l $FRONTEND_PORT &
    FRONTEND_PID=$!
    
    log "Frontend server started with PID: $FRONTEND_PID"
    return $FRONTEND_PID
}

# Function to wait for API to be ready
wait_for_api() {
    local max_attempts=30
    local attempt=1
    
    log "Waiting for API server to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://localhost:$API_PORT/health" > /dev/null 2>&1; then
            log "API server is ready!"
            return 0
        fi
        
        if [ $attempt -eq 1 ]; then
            log "API not ready yet, waiting..."
        fi
        
        sleep 2
        ((attempt++))
    done
    
    error "API server failed to start after $max_attempts attempts"
    return 1
}

# Function to handle shutdown
shutdown() {
    log "Shutting down dashboard services..."
    
    if [ ! -z "${API_PID:-}" ]; then
        log "Stopping API server (PID: $API_PID)..."
        kill -TERM $API_PID 2>/dev/null || true
    fi
    
    if [ ! -z "${FRONTEND_PID:-}" ]; then
        log "Stopping frontend server (PID: $FRONTEND_PID)..."
        kill -TERM $FRONTEND_PID 2>/dev/null || true
    fi
    
    # Wait for graceful shutdown
    sleep 2
    
    log "Dashboard stopped"
    exit 0
}

# Trap signals
trap shutdown SIGTERM SIGINT SIGQUIT

# Start services
start_api
API_PID=$!

# Wait for API to be ready
if ! wait_for_api; then
    error "Failed to start API server"
    shutdown
    exit 1
fi

start_frontend
FRONTEND_PID=$!

log "Dashboard started successfully!"
log "API available at: http://localhost:$API_PORT"
log "Frontend available at: http://localhost:$FRONTEND_PORT"
log "Health check: http://localhost:$API_PORT/health"

# Keep the script running and monitor processes
while true; do
    # Check if API process is still running
    if ! kill -0 $API_PID 2>/dev/null; then
        error "API server process died unexpectedly"
        shutdown
        exit 1
    fi
    
    # Check if frontend process is still running
    if ! kill -0 $FRONTEND_PID 2>/dev/null; then
        error "Frontend server process died unexpectedly"
        shutdown
        exit 1
    fi
    
    # Sleep before checking again
    sleep 10
done