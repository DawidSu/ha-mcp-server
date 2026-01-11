#!/bin/bash

# Home Assistant MCP Server - Einfaches Setup-Script
# Dieses Script hilft beim initialen Setup

set -e

echo "=========================================="
echo "Home Assistant MCP Server Setup"
echo "=========================================="
echo ""

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funktion für farbige Ausgabe
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Prüfe Voraussetzungen
echo "Prüfe Voraussetzungen..."

if ! command -v docker &> /dev/null; then
    print_error "Docker ist nicht installiert!"
    echo "Installiere Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
print_success "Docker gefunden"

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose ist nicht installiert!"
    echo "Installiere Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi
print_success "Docker Compose gefunden"

echo ""
echo "=========================================="
echo "Konfiguration"
echo "=========================================="
echo ""

# Frage nach Home Assistant Config-Pfad
echo "Wo befindet sich dein Home Assistant Config-Verzeichnis?"
echo ""
echo "Beispiele:"
echo "  - /home/user/homeassistant/config"
echo "  - /usr/share/hassio/homeassistant"
echo "  - ~/docker/homeassistant/config"
echo ""
read -p "Pfad eingeben: " HA_PATH

# Normalisiere Pfad (expandiere ~)
HA_PATH="${HA_PATH/#\~/$HOME}"

# Prüfe ob Pfad existiert
if [ ! -d "$HA_PATH" ]; then
    print_error "Verzeichnis $HA_PATH existiert nicht!"
    read -p "Trotzdem fortfahren? (y/n): " continue
    if [ "$continue" != "y" ]; then
        exit 1
    fi
else
    print_success "Home Assistant Config-Verzeichnis gefunden"
    
    # Prüfe ob configuration.yaml existiert
    if [ -f "$HA_PATH/configuration.yaml" ]; then
        print_success "configuration.yaml gefunden"
    else
        print_warning "Keine configuration.yaml gefunden - bist du sicher, dass dies der richtige Pfad ist?"
    fi
fi

# Erstelle .env Datei
echo ""
echo "Erstelle .env Datei..."
cat > .env << EOF
# Home Assistant MCP Server Configuration
# Generiert am $(date)

# Pfad zu deinem Home Assistant Config-Verzeichnis
HA_CONFIG_PATH=$HA_PATH

# Port für den MCP Server (Standard: 3000)
MCP_PORT=3000
EOF

print_success ".env Datei erstellt"

# Backup-Empfehlung
echo ""
echo "=========================================="
echo "Sicherheitshinweise"
echo "=========================================="
echo ""
print_warning "WICHTIG: Erstelle ein Backup deiner Home Assistant Konfiguration!"
echo ""
echo "Backup erstellen:"
echo "  cp -r $HA_PATH ${HA_PATH}-backup-\$(date +%Y%m%d)"
echo ""
read -p "Möchtest du jetzt ein Backup erstellen? (y/n): " create_backup

if [ "$create_backup" = "y" ]; then
    BACKUP_PATH="${HA_PATH}-backup-$(date +%Y%m%d-%H%M%S)"
    echo "Erstelle Backup nach $BACKUP_PATH..."
    cp -r "$HA_PATH" "$BACKUP_PATH"
    print_success "Backup erstellt: $BACKUP_PATH"
fi

# Git-Empfehlung
echo ""
if [ ! -d "$HA_PATH/.git" ]; then
    print_warning "Git-Versionierung ist nicht aktiviert!"
    echo ""
    echo "Empfehlung: Initialisiere Git für deine HA-Config:"
    echo "  cd $HA_PATH"
    echo "  git init"
    echo "  git add ."
    echo "  git commit -m 'Initial commit vor MCP Server'"
    echo ""
    read -p "Möchtest du Git jetzt initialisieren? (y/n): " init_git
    
    if [ "$init_git" = "y" ]; then
        cd "$HA_PATH"
        git init
        git add .
        git commit -m "Initial commit vor MCP Server"
        print_success "Git initialisiert"
        cd - > /dev/null
    fi
else
    print_success "Git-Versionierung bereits aktiv"
fi

# Docker Container starten
echo ""
echo "=========================================="
echo "Container starten"
echo "=========================================="
echo ""
read -p "Möchtest du den Container jetzt starten? (y/n): " start_container

if [ "$start_container" = "y" ]; then
    echo "Baue Docker Image..."
    docker-compose build
    
    echo ""
    echo "Starte Container..."
    docker-compose up -d
    
    echo ""
    echo "Warte auf Container-Start..."
    sleep 5
    
    if docker ps | grep -q homeassistant-mcp-server; then
        print_success "Container läuft!"
        
        echo ""
        echo "Container-Info:"
        docker ps | grep homeassistant-mcp-server
        
        echo ""
        echo "Logs:"
        docker-compose logs --tail=20
    else
        print_error "Container konnte nicht gestartet werden"
        echo ""
        echo "Logs:"
        docker-compose logs
        exit 1
    fi
fi

# Claude Desktop Konfiguration
echo ""
echo "=========================================="
echo "Claude Desktop Konfiguration"
echo "=========================================="
echo ""
echo "Um Claude Desktop zu verbinden, füge folgendes zu deiner Claude Config hinzu:"
echo ""

CLAUDE_CONFIG='{
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

echo "$CLAUDE_CONFIG"

echo ""
echo "Config-Datei Pfade:"
echo "  macOS:   ~/Library/Application Support/Claude/claude_desktop_config.json"
echo "  Windows: %APPDATA%\\Claude\\claude_desktop_config.json"
echo "  Linux:   ~/.config/Claude/claude_desktop_config.json"

# Versuche Config automatisch zu erstellen (nur macOS/Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    CLAUDE_CONFIG_PATH="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    CLAUDE_CONFIG_PATH="$HOME/.config/Claude/claude_desktop_config.json"
fi

if [ ! -z "$CLAUDE_CONFIG_PATH" ]; then
    echo ""
    read -p "Soll die Config automatisch erstellt werden? (y/n): " create_config
    
    if [ "$create_config" = "y" ]; then
        mkdir -p "$(dirname "$CLAUDE_CONFIG_PATH")"
        echo "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG_PATH"
        print_success "Claude Desktop Config erstellt: $CLAUDE_CONFIG_PATH"
        print_warning "Bitte starte Claude Desktop neu!"
    fi
fi

# Fertig!
echo ""
echo "=========================================="
echo "Setup abgeschlossen!"
echo "=========================================="
echo ""
print_success "MCP Server ist bereit!"
echo ""
echo "Nächste Schritte:"
echo "  1. Starte Claude Desktop App"
echo "  2. Frage Claude: 'Kannst du meine Home Assistant Konfiguration sehen?'"
echo "  3. Lass Claude deine Automationen erstellen!"
echo ""
echo "Nützliche Befehle:"
echo "  docker-compose logs -f          # Logs anzeigen"
echo "  docker-compose restart          # Container neu starten"
echo "  docker-compose down             # Container stoppen"
echo ""
echo "Dokumentation: README.md"
echo ""
print_success "Viel Erfolg! 🏠🤖"
