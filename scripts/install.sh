#!/bin/bash

# Enhanced installation script for MCP Server
# Sets up all automation and monitoring features

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Check if running as root
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. Consider using a non-root user for Docker."
    fi
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y \
            docker.io \
            docker-compose \
            python3 \
            python3-pip \
            yamllint \
            jq \
            inotify-tools \
            curl \
            git \
            bc
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        sudo yum update -y
        sudo yum install -y \
            docker \
            docker-compose \
            python3 \
            python3-pip \
            jq \
            inotify-tools \
            curl \
            git \
            bc
    elif command -v apk >/dev/null 2>&1; then
        # Alpine
        sudo apk add --no-cache \
            docker \
            docker-compose \
            python3 \
            py3-pip \
            jq \
            inotify-tools \
            curl \
            git \
            bc
    else
        log_warning "Unknown package manager. Please install dependencies manually."
    fi
    
    # Install Python packages
    pip3 install --user yamllint pyyaml
    
    log_info "Dependencies installed successfully"
}

# Setup Docker
setup_docker() {
    log_info "Setting up Docker..."
    
    # Start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    log_info "Docker setup complete. You may need to log out and back in for group changes to take effect."
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p "$PROJECT_DIR"/{logs,backups,scripts}
    mkdir -p "$PROJECT_DIR"/.github/workflows
    
    # Set permissions
    chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    
    log_info "Directories created"
}

# Setup environment file
setup_environment() {
    log_info "Setting up environment configuration..."
    
    if [ ! -f "$PROJECT_DIR/.env" ]; then
        if [ -f "$PROJECT_DIR/.env.example" ]; then
            cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
            log_info "Created .env from template"
        else
            log_error ".env.example not found"
            return 1
        fi
    else
        log_info ".env file already exists"
    fi
}

# Configure Home Assistant path
configure_ha_path() {
    local ha_path=""
    
    # Try to auto-detect HA path
    local possible_paths=(
        "/usr/share/hassio/homeassistant"
        "/config"
        "/home/homeassistant/.homeassistant"
        "$(dirname "$(find /home -name "configuration.yaml" 2>/dev/null | head -1)" 2>/dev/null)"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/configuration.yaml" ]; then
            ha_path="$path"
            break
        fi
    done
    
    if [ -z "$ha_path" ]; then
        echo ""
        echo "Home Assistant configuration directory not auto-detected."
        echo "Please enter the path to your Home Assistant config directory:"
        echo "(This should contain configuration.yaml)"
        read -p "Path: " ha_path
        
        ha_path="${ha_path/#\~/$HOME}"  # Expand tilde
    fi
    
    if [ ! -d "$ha_path" ]; then
        log_warning "Directory '$ha_path' does not exist"
        read -p "Create it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$ha_path"
        fi
    fi
    
    # Update .env file
    sed -i "s|HA_CONFIG_PATH=.*|HA_CONFIG_PATH=$ha_path|" "$PROJECT_DIR/.env"
    log_info "Home Assistant path configured: $ha_path"
}

# Setup Git repository
setup_git() {
    log_info "Setting up Git repository..."
    
    cd "$PROJECT_DIR"
    
    if [ ! -d ".git" ]; then
        git init
        
        # Create .gitignore
        cat > .gitignore <<EOF
.env
logs/*
backups/*
*.log
*.pid
__pycache__/
*.pyc
.DS_Store
Thumbs.db
EOF
        
        git add .
        git commit -m "Initial commit - Enhanced MCP Server setup"
        
        log_info "Git repository initialized"
    else
        log_info "Git repository already exists"
    fi
}

# Install monitoring services
setup_monitoring() {
    log_info "Setting up monitoring..."
    
    # Create systemd service for monitoring (optional)
    if command -v systemctl >/dev/null 2>&1; then
        cat > /tmp/mcp-monitor.service <<EOF
[Unit]
Description=MCP Server Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/monitor.sh
Restart=always
RestartSec=10
User=$USER
WorkingDirectory=$PROJECT_DIR

[Install]
WantedBy=multi-user.target
EOF
        
        read -p "Install monitoring as systemd service? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo cp /tmp/mcp-monitor.service /etc/systemd/system/
            sudo systemctl enable mcp-monitor.service
            log_info "Monitoring service installed"
        fi
        
        rm /tmp/mcp-monitor.service
    fi
}

# Setup cron jobs for automation
setup_cron() {
    log_info "Setting up automated tasks..."
    
    # Create cron jobs
    local cron_entries=""
    
    # Daily backup
    cron_entries+="0 2 * * * $SCRIPT_DIR/backup.sh create daily >/dev/null 2>&1"$'\n'
    
    # Weekly cleanup
    cron_entries+="0 3 * * 0 $SCRIPT_DIR/backup.sh cleanup >/dev/null 2>&1"$'\n'
    
    # Update check (weekly)
    cron_entries+="0 1 * * 1 $SCRIPT_DIR/update.sh check >/dev/null 2>&1"$'\n'
    
    # Configuration validation (daily)
    cron_entries+="30 1 * * * $SCRIPT_DIR/validate-config.sh check >/dev/null 2>&1"$'\n'
    
    echo "$cron_entries" | crontab -
    
    log_info "Automated tasks configured:"
    echo "  - Daily backups at 2:00 AM"
    echo "  - Weekly cleanup at 3:00 AM on Sundays"
    echo "  - Weekly update check at 1:00 AM on Mondays"
    echo "  - Daily config validation at 1:30 AM"
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Test Docker
    if docker --version >/dev/null 2>&1; then
        log_info "✓ Docker is working"
    else
        log_error "✗ Docker test failed"
        return 1
    fi
    
    # Test scripts
    for script in backup.sh monitor.sh validate-config.sh update.sh; do
        if [ -x "$SCRIPT_DIR/$script" ]; then
            log_info "✓ $script is executable"
        else
            log_warning "⚠ $script is not executable"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    # Test Python dependencies
    if python3 -c "import yaml" >/dev/null 2>&1; then
        log_info "✓ Python YAML support available"
    else
        log_warning "⚠ Python YAML module not found"
    fi
    
    log_info "Installation test completed"
}

# Build and start services
build_and_start() {
    log_info "Building and starting MCP Server..."
    
    cd "$PROJECT_DIR"
    
    # Build containers
    docker-compose build
    
    # Start services
    docker-compose up -d
    
    # Wait for startup
    sleep 10
    
    # Check status
    if docker-compose ps | grep -q "Up"; then
        log_info "✓ MCP Server is running!"
        
        # Show status
        docker-compose ps
        
        # Show logs
        echo ""
        log_info "Recent logs:"
        docker-compose logs --tail=10
    else
        log_error "✗ Failed to start MCP Server"
        docker-compose logs
        return 1
    fi
}

# Generate Claude configuration
generate_claude_config() {
    log_info "Generating Claude Desktop configuration..."
    
    local claude_config='{
  "mcpServers": {
    "homeassistant": {
      "command": "docker",
      "args": [
        "exec",
        "-i",
        "homeassistant-mcp-server",
        "npx",
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/config"
      ]
    }
  }
}'
    
    echo "$claude_config" > "$PROJECT_DIR/claude_desktop_config.json"
    
    log_info "Claude config saved to: $PROJECT_DIR/claude_desktop_config.json"
    
    # Try to install it automatically
    local claude_config_dirs=(
        "$HOME/Library/Application Support/Claude"
        "$HOME/.config/Claude"
        "$APPDATA/Claude"
    )
    
    for config_dir in "${claude_config_dirs[@]}"; do
        if [ -d "$(dirname "$config_dir")" ]; then
            mkdir -p "$config_dir"
            cp "$PROJECT_DIR/claude_desktop_config.json" "$config_dir/claude_desktop_config.json"
            log_info "Claude config installed to: $config_dir/claude_desktop_config.json"
            break
        fi
    done
}

# Main installation function
main() {
    echo "=========================================="
    echo "Enhanced MCP Server Installation"
    echo "=========================================="
    echo ""
    
    check_permissions
    install_dependencies
    setup_docker
    create_directories
    setup_environment
    configure_ha_path
    setup_git
    setup_monitoring
    setup_cron
    test_installation
    build_and_start
    generate_claude_config
    
    echo ""
    echo "=========================================="
    echo "Installation Complete!"
    echo "=========================================="
    echo ""
    log_info "✅ MCP Server with enhanced automation is now running!"
    echo ""
    echo "🔧 Available tools:"
    echo "  $SCRIPT_DIR/backup.sh      - Backup management"
    echo "  $SCRIPT_DIR/monitor.sh     - System monitoring"
    echo "  $SCRIPT_DIR/validate-config.sh - Config validation"
    echo "  $SCRIPT_DIR/update.sh      - Update management"
    echo ""
    echo "📊 Monitoring:"
    echo "  docker-compose logs -f     - View live logs"
    echo "  docker-compose ps          - Check service status"
    echo ""
    echo "🎯 Next steps:"
    echo "  1. Restart Claude Desktop"
    echo "  2. Test with: 'Can you see my Home Assistant config?'"
    echo "  3. Start creating automations with Claude!"
    echo ""
    log_info "Documentation: $PROJECT_DIR/README.md"
}

# Run main function if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi