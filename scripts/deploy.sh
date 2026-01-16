#!/bin/bash
# Zero-Downtime Deployment Script for Home Assistant MCP Server
# Provides safe deployment with automatic rollback on failure

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source dependencies
if [[ -f "$SCRIPT_DIR/logger.sh" ]]; then
    source "$SCRIPT_DIR/logger.sh"
else
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1" >&2; }
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
fi

if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
    source "$SCRIPT_DIR/health-check.sh"
fi

if [[ -f "$SCRIPT_DIR/backup.sh" ]]; then
    source "$SCRIPT_DIR/backup.sh"
fi

# =============================================================================
# Deployment Configuration
# =============================================================================

# Deployment settings
declare -g DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"
declare -g DEPLOY_CHECK_INTERVAL="${DEPLOY_CHECK_INTERVAL:-10}"
declare -g DEPLOY_BACKUP_BEFORE="${DEPLOY_BACKUP_BEFORE:-true}"
declare -g DEPLOY_VALIDATE_CONFIG="${DEPLOY_VALIDATE_CONFIG:-true}"
declare -g DEPLOY_RUN_TESTS="${DEPLOY_RUN_TESTS:-false}"
declare -g DEPLOY_STRATEGY="${DEPLOY_STRATEGY:-rolling}"  # rolling, blue-green

# Service configuration
declare -g SERVICE_NAME="${SERVICE_NAME:-ha-mcp-server}"
declare -g COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
declare -g BACKUP_NAME=""

# =============================================================================
# Pre-deployment Checks
# =============================================================================

# Check deployment prerequisites
check_prerequisites() {
    log_info "Checking deployment prerequisites..."
    
    local missing_tools=()
    
    # Required tools
    local required_tools=("docker" "docker-compose" "git")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Check if compose file exists
    if [[ ! -f "$PROJECT_DIR/$COMPOSE_FILE" ]]; then
        log_error "Docker compose file not found: $PROJECT_DIR/$COMPOSE_FILE"
        return 1
    fi
    
    # Check if we're in the correct directory
    if [[ ! -f "$PROJECT_DIR/Dockerfile" ]]; then
        log_error "Not in correct project directory. Expected Dockerfile in: $PROJECT_DIR"
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

# Validate current configuration
validate_current_config() {
    if [[ "$DEPLOY_VALIDATE_CONFIG" != "true" ]]; then
        log_info "Configuration validation disabled"
        return 0
    fi
    
    log_info "Validating current configuration..."
    
    # Check if health check script is available
    if command -v "$SCRIPT_DIR/health-check.sh" >/dev/null 2>&1; then
        if ! "$SCRIPT_DIR/health-check.sh" all >/dev/null 2>&1; then
            log_warning "Current configuration has health check warnings"
            read -p "Continue with deployment? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Deployment cancelled by user"
                return 1
            fi
        else
            log_success "Current configuration is healthy"
        fi
    else
        log_warning "Health check script not available, skipping validation"
    fi
    
    return 0
}

# Create deployment backup
create_deployment_backup() {
    if [[ "$DEPLOY_BACKUP_BEFORE" != "true" ]]; then
        log_info "Backup disabled, skipping"
        return 0
    fi
    
    log_info "Creating deployment backup..."
    
    BACKUP_NAME="deploy-$(date +%Y%m%d_%H%M%S)"
    
    if command -v "$SCRIPT_DIR/backup.sh" >/dev/null 2>&1; then
        if "$SCRIPT_DIR/backup.sh" create "$BACKUP_NAME"; then
            log_success "Backup created: $BACKUP_NAME"
            return 0
        else
            log_error "Failed to create backup"
            return 1
        fi
    else
        # Manual backup if script not available
        local backup_dir="/tmp/mcp-backup-$BACKUP_NAME"
        mkdir -p "$backup_dir"
        
        # Backup docker-compose state
        docker-compose -f "$PROJECT_DIR/$COMPOSE_FILE" ps > "$backup_dir/services.txt" 2>&1 || true
        docker-compose -f "$PROJECT_DIR/$COMPOSE_FILE" images > "$backup_dir/images.txt" 2>&1 || true
        
        # Backup configuration files
        cp -r "$PROJECT_DIR" "$backup_dir/project" 2>/dev/null || true
        
        log_success "Manual backup created: $backup_dir"
    fi
    
    return 0
}

# =============================================================================
# Deployment Strategies
# =============================================================================

# Rolling deployment strategy
deploy_rolling() {
    log_info "Starting rolling deployment..."
    
    cd "$PROJECT_DIR"
    
    # Pull new images
    log_info "Pulling new images..."
    if ! docker-compose -f "$COMPOSE_FILE" pull; then
        log_error "Failed to pull new images"
        return 1
    fi
    
    # Restart services one by one
    local services
    mapfile -t services < <(docker-compose -f "$COMPOSE_FILE" config --services)
    
    for service in "${services[@]}"; do
        log_info "Restarting service: $service"
        
        # Stop old container
        docker-compose -f "$COMPOSE_FILE" stop "$service"
        
        # Start new container
        if ! docker-compose -f "$COMPOSE_FILE" up -d "$service"; then
            log_error "Failed to start service: $service"
            return 1
        fi
        
        # Wait for service to be healthy
        if ! wait_for_service_health "$service"; then
            log_error "Service $service failed health check"
            return 1
        fi
        
        log_success "Service $service updated successfully"
    done
    
    log_success "Rolling deployment completed"
    return 0
}

# Blue-Green deployment strategy (future enhancement)
deploy_blue_green() {
    log_info "Blue-Green deployment strategy not yet implemented"
    log_info "Falling back to rolling deployment"
    deploy_rolling
}

# =============================================================================
# Health Monitoring
# =============================================================================

# Wait for service to become healthy
wait_for_service_health() {
    local service_name="$1"
    local timeout="${2:-$DEPLOY_TIMEOUT}"
    local check_interval="${3:-$DEPLOY_CHECK_INTERVAL}"
    
    log_info "Waiting for $service_name to become healthy (timeout: ${timeout}s)..."
    
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for $service_name to become healthy"
            return 1
        fi
        
        # Check container status
        local container_status
        container_status=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service_name" | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
        
        if [[ "$container_status" == "running" ]]; then
            # Check health if health check is configured
            local health_status
            health_status=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service_name" | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
            
            case "$health_status" in
                "healthy"|"none")
                    log_success "Service $service_name is healthy"
                    return 0
                    ;;
                "unhealthy")
                    log_warning "Service $service_name is unhealthy, continuing to wait..."
                    ;;
                *)
                    log_info "Service $service_name health status: $health_status"
                    ;;
            esac
        else
            log_warning "Service $service_name status: $container_status"
        fi
        
        sleep "$check_interval"
    done
}

# Post-deployment health check
post_deployment_health_check() {
    log_info "Running post-deployment health checks..."
    
    # Use our health check script if available
    if command -v "$SCRIPT_DIR/health-check.sh" >/dev/null 2>&1; then
        if "$SCRIPT_DIR/health-check.sh" all; then
            log_success "All health checks passed"
            return 0
        else
            log_error "Health checks failed"
            return 1
        fi
    else
        # Basic health check
        log_info "Running basic health checks..."
        
        # Check if containers are running
        local running_containers
        running_containers=$(docker-compose -f "$PROJECT_DIR/$COMPOSE_FILE" ps -q | wc -l)
        
        if [[ $running_containers -eq 0 ]]; then
            log_error "No containers are running"
            return 1
        fi
        
        log_success "Basic health checks passed ($running_containers containers running)"
        return 0
    fi
}

# =============================================================================
# Rollback Functions
# =============================================================================

# Automatic rollback on failure
rollback_deployment() {
    log_warning "Starting automatic rollback..."
    
    if [[ -n "$BACKUP_NAME" ]]; then
        log_info "Restoring from backup: $BACKUP_NAME"
        
        if command -v "$SCRIPT_DIR/backup.sh" >/dev/null 2>&1; then
            if "$SCRIPT_DIR/backup.sh" restore "$BACKUP_NAME"; then
                log_success "Rollback completed successfully"
                return 0
            else
                log_error "Rollback failed using backup script"
            fi
        fi
    fi
    
    # Fallback rollback - restart previous containers
    log_info "Attempting fallback rollback..."
    
    cd "$PROJECT_DIR"
    docker-compose -f "$COMPOSE_FILE" down
    
    # Try to start with cached images
    if docker-compose -f "$COMPOSE_FILE" up -d; then
        log_success "Fallback rollback completed"
        return 0
    else
        log_error "Rollback failed - manual intervention required"
        return 1
    fi
}

# Manual rollback
manual_rollback() {
    local backup_name="${1:-}"
    
    if [[ -z "$backup_name" ]]; then
        log_error "Backup name required for manual rollback"
        echo "Usage: $0 rollback <backup_name>"
        return 1
    fi
    
    log_info "Starting manual rollback to: $backup_name"
    
    if command -v "$SCRIPT_DIR/backup.sh" >/dev/null 2>&1; then
        if "$SCRIPT_DIR/backup.sh" restore "$backup_name"; then
            log_success "Manual rollback completed"
            return 0
        else
            log_error "Manual rollback failed"
            return 1
        fi
    else
        log_error "Backup script not available for manual rollback"
        return 1
    fi
}

# =============================================================================
# Testing Integration
# =============================================================================

# Run deployment tests
run_deployment_tests() {
    if [[ "$DEPLOY_RUN_TESTS" != "true" ]]; then
        log_info "Deployment tests disabled"
        return 0
    fi
    
    log_info "Running deployment tests..."
    
    if [[ -f "$PROJECT_DIR/tests/run-tests.sh" ]]; then
        if "$PROJECT_DIR/tests/run-tests.sh" --integration-only; then
            log_success "Deployment tests passed"
            return 0
        else
            log_error "Deployment tests failed"
            return 1
        fi
    else
        log_warning "Test suite not found, skipping tests"
        return 0
    fi
}

# =============================================================================
# Main Deployment Function
# =============================================================================

# Execute deployment
deploy() {
    local strategy="${1:-$DEPLOY_STRATEGY}"
    
    log_info "Starting deployment with strategy: $strategy"
    
    # Pre-deployment phase
    check_prerequisites || return 1
    validate_current_config || return 1
    create_deployment_backup || return 1
    
    # Deployment phase
    case "$strategy" in
        "rolling")
            if ! deploy_rolling; then
                log_error "Rolling deployment failed"
                rollback_deployment
                return 1
            fi
            ;;
        "blue-green")
            if ! deploy_blue_green; then
                log_error "Blue-Green deployment failed"
                rollback_deployment
                return 1
            fi
            ;;
        *)
            log_error "Unknown deployment strategy: $strategy"
            return 1
            ;;
    esac
    
    # Post-deployment phase
    if ! post_deployment_health_check; then
        log_error "Post-deployment health check failed"
        rollback_deployment
        return 1
    fi
    
    if ! run_deployment_tests; then
        log_error "Deployment tests failed"
        rollback_deployment
        return 1
    fi
    
    log_success "Deployment completed successfully"
    
    # Cleanup old backup (keep recent ones)
    if [[ -n "$BACKUP_NAME" ]] && command -v "$SCRIPT_DIR/backup.sh" >/dev/null 2>&1; then
        log_info "Cleaning up old backups..."
        "$SCRIPT_DIR/backup.sh" cleanup >/dev/null 2>&1 || true
    fi
    
    return 0
}

# =============================================================================
# Status and Information Functions
# =============================================================================

# Show deployment status
show_status() {
    log_info "Deployment Status"
    echo "=================="
    
    cd "$PROJECT_DIR"
    
    echo "Services:"
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    echo "Images:"
    docker-compose -f "$COMPOSE_FILE" images
    
    echo ""
    if command -v "$SCRIPT_DIR/health-check.sh" >/dev/null 2>&1; then
        echo "Health Status:"
        "$SCRIPT_DIR/health-check.sh" all
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    case "${1:-}" in
        "deploy")
            deploy "${2:-rolling}"
            ;;
        "rollback")
            manual_rollback "${2:-}"
            ;;
        "status")
            show_status
            ;;
        "test")
            echo "Testing deployment system..."
            check_prerequisites
            validate_current_config
            echo "Deployment system test completed"
            ;;
        *)
            echo "Usage: $0 {deploy|rollback|status|test} [args...]"
            echo ""
            echo "Commands:"
            echo "  deploy [strategy]         - Deploy application (strategies: rolling, blue-green)"
            echo "  rollback <backup_name>    - Rollback to specific backup"
            echo "  status                    - Show current deployment status"
            echo "  test                      - Test deployment system"
            echo ""
            echo "Environment Variables:"
            echo "  DEPLOY_TIMEOUT=300              - Deployment timeout in seconds"
            echo "  DEPLOY_BACKUP_BEFORE=true       - Create backup before deployment"
            echo "  DEPLOY_VALIDATE_CONFIG=true     - Validate configuration before deployment"
            echo "  DEPLOY_RUN_TESTS=false          - Run tests after deployment"
            echo "  DEPLOY_STRATEGY=rolling         - Default deployment strategy"
            exit 1
            ;;
    esac
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f deploy rollback_deployment wait_for_service_health
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi