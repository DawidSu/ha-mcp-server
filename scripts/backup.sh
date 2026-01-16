#!/bin/bash

# Automatic backup script for Home Assistant configuration
# Creates incremental backups before Claude makes changes

set -e

# Configuration
HA_CONFIG_PATH=${HA_CONFIG_PATH:-/config}
BACKUP_DIR=${BACKUP_DIR:-/backups}
MAX_BACKUPS=${MAX_BACKUPS:-30}
BACKUP_BEFORE_CHANGE=${BACKUP_BEFORE_CHANGE:-true}
USE_GIT=${USE_GIT:-true}

# Source logger if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/logger.sh" ]; then
    source "$SCRIPT_DIR/logger.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1"; }
    log_debug() { echo "[DEBUG] $1"; }
fi

# Create backup directory if it doesn't exist
ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
}

# Function to create a timestamped backup
create_backup() {
    local backup_type=${1:-"manual"}
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="ha_backup_${backup_type}_${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_info "Creating backup: $backup_name"
    
    # Check if source exists
    if [ ! -d "$HA_CONFIG_PATH" ]; then
        log_error "Source directory does not exist: $HA_CONFIG_PATH"
        return 1
    fi
    
    # Calculate size before backup
    local size_before=$(du -sh "$HA_CONFIG_PATH" | cut -f1)
    log_info "Configuration size: $size_before"
    
    # Create tar archive with compression
    log_info "Creating compressed archive..."
    if tar -czf "${backup_path}.tar.gz" \
        --exclude='*.log' \
        --exclude='*.db' \
        --exclude='*.db-shm' \
        --exclude='*.db-wal' \
        --exclude='.HA_VERSION' \
        --exclude='home-assistant_v2.db' \
        --exclude='.storage/core.entity_registry' \
        --exclude='.storage/core.device_registry' \
        --exclude='.cloud' \
        -C "$(dirname "$HA_CONFIG_PATH")" \
        "$(basename "$HA_CONFIG_PATH")" 2>/dev/null; then
        
        local backup_size=$(du -sh "${backup_path}.tar.gz" | cut -f1)
        log_info "Backup created successfully: ${backup_path}.tar.gz (Size: $backup_size)"
        
        # Create metadata file
        cat > "${backup_path}.meta" <<EOF
{
    "timestamp": "$timestamp",
    "type": "$backup_type",
    "source": "$HA_CONFIG_PATH",
    "size": "$backup_size",
    "date": "$(date -Iseconds)",
    "files_count": $(find "$HA_CONFIG_PATH" -type f 2>/dev/null | wc -l),
    "hostname": "$(hostname)"
}
EOF
        
        # Verify backup
        if tar -tzf "${backup_path}.tar.gz" > /dev/null 2>&1; then
            log_info "Backup verified successfully"
            echo "${backup_path}.tar.gz"
            return 0
        else
            log_error "Backup verification failed"
            rm -f "${backup_path}.tar.gz" "${backup_path}.meta"
            return 1
        fi
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# Function to create Git backup
create_git_backup() {
    local message=${1:-"Automatic backup before changes"}
    
    if [ "$USE_GIT" != "true" ]; then
        log_debug "Git backups disabled"
        return 0
    fi
    
    cd "$HA_CONFIG_PATH" 2>/dev/null || {
        log_warning "Cannot change to config directory: $HA_CONFIG_PATH"
        return 1
    }
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        log_warning "Git is not installed, skipping git backup"
        return 1
    fi
    
    # Initialize git if needed
    if [ ! -d ".git" ]; then
        log_info "Initializing Git repository..."
        git init
        
        # Create .gitignore if it doesn't exist
        if [ ! -f ".gitignore" ]; then
            cat > .gitignore <<EOF
*.log
*.db
*.db-shm
*.db-wal
.HA_VERSION
home-assistant_v2.db*
.cloud/
.storage/auth*
.storage/core.entity_registry
.storage/core.device_registry
secrets.yaml
known_devices.yaml
*.pid
tts/
deps/
__pycache__/
*.pyc
EOF
            log_info "Created .gitignore file"
        fi
        
        # Initial commit
        git add .
        git commit -m "Initial commit - Automatic backup system" || true
    fi
    
    # Check for changes
    if [ -z "$(git status --porcelain)" ]; then
        log_debug "No changes to commit"
        return 0
    fi
    
    # Stage all changes
    git add -A
    
    # Create commit
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if git commit -m "$message" -m "Timestamp: $timestamp" -m "Automated backup by MCP Server"; then
        log_info "Git commit created successfully"
        
        # Show what was changed
        local changes=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1)
        log_info "Changes: $changes"
        
        # Create tag for important backups
        if [[ "$message" == *"before Claude"* ]]; then
            local tag="backup-$(date +%Y%m%d-%H%M%S)"
            git tag -a "$tag" -m "$message"
            log_info "Tagged as: $tag"
        fi
        
        return 0
    else
        log_error "Failed to create git commit"
        return 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping last $MAX_BACKUPS)"
    
    # Count current backups
    local backup_count=$(find "$BACKUP_DIR" -name "ha_backup_*.tar.gz" 2>/dev/null | wc -l)
    
    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        local to_delete=$((backup_count - MAX_BACKUPS))
        log_info "Removing $to_delete old backups"
        
        # Delete oldest backups
        find "$BACKUP_DIR" -name "ha_backup_*.tar.gz" -print0 2>/dev/null | \
            xargs -0 ls -t | \
            tail -n "$to_delete" | \
            while read -r backup_file; do
                log_debug "Deleting: $(basename "$backup_file")"
                rm -f "$backup_file" "${backup_file%.tar.gz}.meta"
            done
    fi
    
    # Clean up Git history if it's too large
    if [ "$USE_GIT" = "true" ] && [ -d "$HA_CONFIG_PATH/.git" ]; then
        local git_size=$(du -sh "$HA_CONFIG_PATH/.git" 2>/dev/null | cut -f1)
        log_debug "Git repository size: $git_size"
        
        # If git is over 100MB, consider cleanup
        local git_size_mb=$(du -sm "$HA_CONFIG_PATH/.git" 2>/dev/null | cut -f1)
        if [ "$git_size_mb" -gt 100 ]; then
            log_warning "Git repository is large (${git_size}), consider running git gc"
            cd "$HA_CONFIG_PATH" && git gc --auto
        fi
    fi
}

# Function to restore from backup
restore_backup() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        log_error "No backup file specified"
        return 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_warning "Restoring from backup: $backup_file"
    log_warning "This will overwrite current configuration!"
    
    # Create safety backup of current state
    create_backup "pre-restore" || {
        log_error "Failed to create safety backup"
        return 1
    }
    
    # Extract backup
    local temp_dir="/tmp/restore_$$"
    mkdir -p "$temp_dir"
    
    if tar -xzf "$backup_file" -C "$temp_dir"; then
        log_info "Backup extracted successfully"
        
        # Sync files
        if rsync -av --delete \
            --exclude='.git' \
            --exclude='*.log' \
            --exclude='*.db' \
            --exclude='*.pid' \
            "$temp_dir/$(basename "$HA_CONFIG_PATH")/" "$HA_CONFIG_PATH/"; then
            
            log_info "Configuration restored successfully"
            rm -rf "$temp_dir"
            return 0
        else
            log_error "Failed to sync restored files"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_error "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to list available backups
list_backups() {
    log_info "Available backups in $BACKUP_DIR:"
    
    find "$BACKUP_DIR" -name "ha_backup_*.tar.gz" -print0 2>/dev/null | \
        xargs -0 ls -lht | \
        while read -r line; do
            echo "  $line"
            
            # Show metadata if available
            local backup_file=$(echo "$line" | awk '{print $NF}')
            local meta_file="${backup_file%.tar.gz}.meta"
            if [ -f "$meta_file" ]; then
                local backup_type=$(grep '"type"' "$meta_file" | cut -d'"' -f4)
                local backup_date=$(grep '"date"' "$meta_file" | cut -d'"' -f4)
                echo "    Type: $backup_type, Date: $backup_date"
            fi
        done
    
    # Show git tags if available
    if [ "$USE_GIT" = "true" ] && [ -d "$HA_CONFIG_PATH/.git" ]; then
        echo ""
        log_info "Git backup tags:"
        cd "$HA_CONFIG_PATH" && git tag -l "backup-*" | tail -10
    fi
}

# Function to monitor for changes and auto-backup
monitor_changes() {
    log_info "Starting file monitor for automatic backups"
    
    if ! command -v inotifywait &> /dev/null; then
        log_error "inotifywait not installed. Install inotify-tools for monitoring"
        return 1
    fi
    
    local last_backup_time=0
    local min_interval=300  # Minimum 5 minutes between auto-backups
    
    inotifywait -mr \
        --exclude '(\.git|\.log|\.db|\.pid)' \
        -e modify,create,delete,move \
        "$HA_CONFIG_PATH" | \
    while read -r directory event filename; do
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_backup_time))
        
        if [ "$time_diff" -ge "$min_interval" ]; then
            log_info "Change detected: $event $filename"
            
            # Create both file and git backups
            create_backup "auto" && \
            create_git_backup "Auto-backup: $event $filename"
            
            last_backup_time=$current_time
        else
            log_debug "Change detected but skipping backup (too soon): $event $filename"
        fi
    done
}

# Main function
main() {
    local action=${1:-"create"}
    
    ensure_backup_dir
    
    case "$action" in
        create)
            create_backup "${2:-manual}"
            create_git_backup "${3:-Manual backup}"
            cleanup_old_backups
            ;;
        restore)
            restore_backup "$2"
            ;;
        list)
            list_backups
            ;;
        monitor)
            monitor_changes
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        git)
            create_git_backup "${2:-Manual git backup}"
            ;;
        *)
            echo "Usage: $0 {create|restore|list|monitor|cleanup|git} [options]"
            echo ""
            echo "Actions:"
            echo "  create [type] [message]  - Create a new backup"
            echo "  restore <file>          - Restore from backup file"
            echo "  list                    - List available backups"
            echo "  monitor                 - Monitor for changes and auto-backup"
            echo "  cleanup                 - Remove old backups"
            echo "  git [message]          - Create git commit backup"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"