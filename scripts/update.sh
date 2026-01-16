#!/bin/bash

# Update script for MCP Server
# Handles updates for Docker container, npm packages, and addon

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONTAINER_NAME="homeassistant-mcp-server"
BACKUP_BEFORE_UPDATE=${BACKUP_BEFORE_UPDATE:-true}

# Source logger if available
if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1"; }
    log_debug() { echo "[DEBUG] $1"; }
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version management
CURRENT_VERSION_FILE="$PROJECT_DIR/.current_version"
PACKAGE_NAME="@modelcontextprotocol/server-filesystem"

# Function to get current version
get_current_version() {
    if [ -f "$CURRENT_VERSION_FILE" ]; then
        cat "$CURRENT_VERSION_FILE"
    else
        # Try to get from running container
        if docker exec "$CONTAINER_NAME" npm list "$PACKAGE_NAME" 2>/dev/null | grep "$PACKAGE_NAME"; then
            docker exec "$CONTAINER_NAME" npm list "$PACKAGE_NAME" 2>/dev/null | \
                grep "$PACKAGE_NAME" | \
                sed 's/.*@//' | \
                head -1
        else
            echo "unknown"
        fi
    fi
}

# Function to get latest version
get_latest_version() {
    npm view "$PACKAGE_NAME" version 2>/dev/null || echo "unknown"
}

# Function to check for updates
check_updates() {
    log_info "Checking for updates..."
    
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"
    
    if [ "$current_version" = "$latest_version" ]; then
        log_info "✓ Already up to date!"
        return 1
    elif [ "$latest_version" = "unknown" ]; then
        log_warning "Could not determine latest version"
        return 1
    else
        log_info "Update available: $current_version → $latest_version"
        return 0
    fi
}

# Function to backup before update
create_update_backup() {
    if [ "$BACKUP_BEFORE_UPDATE" = "true" ]; then
        log_info "Creating backup before update..."
        
        # Backup container data
        local backup_dir="$PROJECT_DIR/backups/update_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Export container
        if docker export "$CONTAINER_NAME" > "$backup_dir/container.tar"; then
            log_info "Container backup saved to $backup_dir/container.tar"
        else
            log_warning "Could not backup container"
        fi
        
        # Backup project files
        tar -czf "$backup_dir/project.tar.gz" \
            --exclude='backups' \
            --exclude='.git' \
            -C "$PROJECT_DIR" . 2>/dev/null
        
        log_info "Project backup saved to $backup_dir/project.tar.gz"
        
        # Save version info
        echo "Backup created: $(date)" > "$backup_dir/info.txt"
        echo "Previous version: $(get_current_version)" >> "$backup_dir/info.txt"
        
        return 0
    fi
    
    return 0
}

# Function to update Docker container
update_docker() {
    log_info "Updating Docker container..."
    
    cd "$PROJECT_DIR"
    
    # Pull latest base image
    log_info "Pulling latest base images..."
    docker-compose pull
    
    # Rebuild container
    log_info "Rebuilding container with latest packages..."
    docker-compose build --no-cache
    
    # Stop old container
    log_info "Stopping current container..."
    docker-compose down
    
    # Start new container
    log_info "Starting updated container..."
    docker-compose up -d
    
    # Wait for container to be ready
    sleep 5
    
    # Verify container is running
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_info "✓ Container updated and running"
        
        # Update version file
        get_latest_version > "$CURRENT_VERSION_FILE"
        
        return 0
    else
        log_error "Container failed to start after update"
        return 1
    fi
}

# Function to update npm packages in running container
update_npm_packages() {
    log_info "Updating npm packages in container..."
    
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log_error "Container is not running"
        return 1
    fi
    
    # Update MCP server package
    log_info "Updating $PACKAGE_NAME..."
    
    if docker exec "$CONTAINER_NAME" npm update -g "$PACKAGE_NAME"; then
        log_info "✓ Package updated successfully"
        
        # Restart container to apply changes
        log_info "Restarting container..."
        docker-compose restart
        
        # Update version file
        get_latest_version > "$CURRENT_VERSION_FILE"
        
        return 0
    else
        log_error "Failed to update package"
        return 1
    fi
}

# Function to update Home Assistant addon
update_addon() {
    log_info "Updating Home Assistant addon configuration..."
    
    local config_file="$PROJECT_DIR/config.yaml"
    
    if [ ! -f "$config_file" ]; then
        log_warning "Addon config.yaml not found"
        return 1
    fi
    
    # Update version in config.yaml
    local new_version=$(get_latest_version)
    
    if [ "$new_version" != "unknown" ]; then
        # Increment addon version
        local current_addon_version=$(grep "^version:" "$config_file" | cut -d'"' -f2)
        local new_addon_version=$(echo "$current_addon_version" | awk -F. '{$NF++; print}' OFS=.)
        
        sed -i "s/^version:.*/version: \"$new_addon_version\"/" "$config_file"
        log_info "Updated addon version to $new_addon_version"
        
        # Update build.yaml if exists
        if [ -f "$PROJECT_DIR/build.yaml" ]; then
            log_info "Updating build.yaml..."
            # Update base image versions if available
            sed -i 's/\(base\/[^:]*:\)[0-9.]*/\1latest/' "$PROJECT_DIR/build.yaml" 2>/dev/null || true
        fi
        
        # Commit changes if in git repository
        if [ -d "$PROJECT_DIR/.git" ]; then
            log_info "Committing addon version update..."
            cd "$PROJECT_DIR"
            git add config.yaml build.yaml 2>/dev/null || true
            git commit -m "Update addon to version $new_addon_version (MCP: $new_version)" 2>/dev/null || true
        fi
        
        return 0
    else
        log_warning "Could not determine version for addon update"
        return 1
    fi
}

# Function to rollback update
rollback_update() {
    local backup_dir=$1
    
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        log_error "Invalid backup directory"
        return 1
    fi
    
    log_warning "Rolling back update from backup: $backup_dir"
    
    # Stop current container
    docker-compose down
    
    # Import container backup if exists
    if [ -f "$backup_dir/container.tar" ]; then
        log_info "Restoring container from backup..."
        docker import "$backup_dir/container.tar" "${CONTAINER_NAME}:rollback"
        
        # Update docker-compose to use rollback image
        sed -i "s|build: .|image: ${CONTAINER_NAME}:rollback|" "$PROJECT_DIR/docker-compose.yml"
        
        # Start rolled back container
        docker-compose up -d
    else
        # Restore project files
        if [ -f "$backup_dir/project.tar.gz" ]; then
            log_info "Restoring project files..."
            tar -xzf "$backup_dir/project.tar.gz" -C "$PROJECT_DIR"
            
            # Rebuild and start
            docker-compose build
            docker-compose up -d
        fi
    fi
    
    log_info "Rollback completed"
}

# Function to test update
test_update() {
    log_info "Testing updated container..."
    
    # Check container health
    local health=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Health.Status}}' 2>/dev/null)
    
    if [ "$health" = "healthy" ]; then
        log_info "✓ Container health check passed"
    else
        log_warning "Container health status: $health"
    fi
    
    # Check if MCP server is responding
    if docker exec "$CONTAINER_NAME" pgrep -f "server-filesystem" > /dev/null; then
        log_info "✓ MCP server process is running"
    else
        log_error "MCP server process not found"
        return 1
    fi
    
    # Check logs for errors
    local recent_logs=$(docker logs "$CONTAINER_NAME" --tail 20 2>&1)
    
    if echo "$recent_logs" | grep -q "ERROR\|CRITICAL\|Failed"; then
        log_warning "Errors found in recent logs:"
        echo "$recent_logs" | grep "ERROR\|CRITICAL\|Failed"
    else
        log_info "✓ No errors in recent logs"
    fi
    
    return 0
}

# Function to clean up old backups
cleanup_old_backups() {
    local backup_dir="$PROJECT_DIR/backups"
    local max_backups=5
    
    if [ -d "$backup_dir" ]; then
        local backup_count=$(find "$backup_dir" -maxdepth 1 -type d -name "update_*" | wc -l)
        
        if [ "$backup_count" -gt "$max_backups" ]; then
            log_info "Cleaning up old update backups..."
            
            # Remove oldest backups
            find "$backup_dir" -maxdepth 1 -type d -name "update_*" -print0 | \
                xargs -0 ls -dt | \
                tail -n +$((max_backups + 1)) | \
                xargs rm -rf
            
            log_info "Removed $((backup_count - max_backups)) old backups"
        fi
    fi
}

# Main update function
main() {
    local action=${1:-check}
    
    case "$action" in
        check)
            check_updates
            ;;
        
        update)
            if check_updates; then
                create_update_backup
                
                if update_docker; then
                    test_update
                    cleanup_old_backups
                    
                    log_info "✓ Update completed successfully!"
                    log_info "New version: $(get_current_version)"
                else
                    log_error "Update failed"
                    
                    # Offer rollback
                    local latest_backup=$(find "$PROJECT_DIR/backups" -maxdepth 1 -type d -name "update_*" | sort -r | head -1)
                    if [ ! -z "$latest_backup" ]; then
                        read -p "Rollback to previous version? (y/n): " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            rollback_update "$latest_backup"
                        fi
                    fi
                    
                    exit 1
                fi
            else
                log_info "No updates available"
            fi
            ;;
        
        npm)
            # Quick npm package update without rebuilding container
            if check_updates; then
                create_update_backup
                update_npm_packages
                test_update
            fi
            ;;
        
        addon)
            # Update addon configuration
            update_addon
            ;;
        
        rollback)
            # Rollback to specific backup
            local backup_dir=${2:-$(find "$PROJECT_DIR/backups" -maxdepth 1 -type d -name "update_*" | sort -r | head -1)}
            rollback_update "$backup_dir"
            ;;
        
        auto)
            # Automatic update with no prompts
            if check_updates; then
                log_info "Running automatic update..."
                create_update_backup
                
                if update_docker && test_update; then
                    cleanup_old_backups
                    log_info "✓ Automatic update completed"
                else
                    log_error "Automatic update failed, rolling back..."
                    local latest_backup=$(find "$PROJECT_DIR/backups" -maxdepth 1 -type d -name "update_*" | sort -r | head -1)
                    rollback_update "$latest_backup"
                    exit 1
                fi
            fi
            ;;
        
        *)
            echo "Usage: $0 {check|update|npm|addon|rollback|auto} [backup_dir]"
            echo ""
            echo "Commands:"
            echo "  check    - Check for available updates"
            echo "  update   - Perform full container update"
            echo "  npm      - Update npm packages only"
            echo "  addon    - Update Home Assistant addon config"
            echo "  rollback - Rollback to previous version"
            echo "  auto     - Automatic update (no prompts)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"