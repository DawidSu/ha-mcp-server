# Changelog

## Version 1.0.0 (2026-01-11)

### 🆕 Erste Release

**Features:**
- ✅ Home Assistant Addon Support
- ✅ MCP Server für Claude Desktop Integration
- ✅ Direkter Zugriff auf HA Konfigurationsdateien
- ✅ Multi-Architektur Support (amd64, aarch64, armv7, armhf, i386)
- ✅ Vollständige Dokumentation

**Unterstützte Funktionen:**
- Automationen erstellen und bearbeiten
- Scripts schreiben und anpassen
- Szenen konfigurieren
- Lovelace UI Dashboards anpassen
- YAML-Konfigurationen optimieren
- Fehlerdiagnose und -behebung

**Installation:**
- Als Home Assistant Addon (empfohlen)
- Als Docker Container (Alternative)

**Dokumentation:**
- Vollständige Installationsanleitung
- Troubleshooting Guide
- Sicherheitshinweise
- Konfigurationsbeispiele

### 📦 Addon-Spezifische Features

- Integrierte bashio Logging
- Automatische Konfigurationsprüfung
- Home Assistant Config Directory Mapping
- Benutzerfreundliche Fehlerbehandlung
- Detaillierte Log-Ausgaben für Debugging

### 🔧 Technische Details

- **Base Images:** Home Assistant Official Base Images
- **Node.js Version:** 20 LTS (über Alpine Package Manager)
- **MCP Server:** @modelcontextprotocol/server-filesystem
- **Port:** 3000 (TCP)
- **Config Path:** /config (gemappt auf HA Config)

### 🛠️ Entwicklung

- GitHub Repository: https://github.com/DawidSu/ha-mcp-server
- Issues und Feature Requests über GitHub Issues
- MIT Lizenz