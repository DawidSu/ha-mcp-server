# Home Assistant MCP Server für Claude

Dieses Projekt stellt einen MCP (Model Context Protocol) Server bereit, der Claude direkten Zugriff auf deine Home Assistant Konfigurationsdateien ermöglicht.

## 🎯 Was kann Claude damit machen?

- ✅ Automationen erstellen und bearbeiten
- ✅ Scripts schreiben und anpassen
- ✅ Szenen konfigurieren
- ✅ Lovelace UI Dashboards anpassen
- ✅ YAML-Konfigurationen optimieren
- ✅ Fehler in Configs finden und beheben
- ✅ Neue Integrationen konfigurieren

## 🏠 Installation als Home Assistant Addon (Empfohlen)

### ⚡ Schnellinstallation

1. **Addon Repository hinzufügen:**
   - Gehe zu **Einstellungen** → **Add-ons** → **Add-on Store**
   - Klicke auf **⋮** → **Repositories**
   - Füge hinzu: `https://github.com/DawidSu/ha-mcp-server`

2. **Addon installieren:**
   - Suche nach "Claude MCP Server"
   - Klicke **Installieren** → **Starten**

3. **Claude Desktop konfigurieren:**
   - Siehe [Addon-Dokumentation](DOCS.md) für Details

**✅ Vorteile des Addons:**
- ✅ Einfache Installation über Home Assistant UI
- ✅ Automatisches Update-Management
- ✅ Integrierte Logs und Monitoring
- ✅ Keine Docker-Kenntnisse erforderlich
- ✅ Läuft nativ in Home Assistant

---

## 🐳 Alternative: Docker Installation

**Nur verwenden wenn das Addon nicht funktioniert**

### 📋 Voraussetzungen für Docker

- Docker und Docker Compose installiert
- Home Assistant läuft (egal ob als Docker, HAOS, oder Core Installation)
- Zugriff auf das Home Assistant Config-Verzeichnis
- Claude Desktop App

### Schritt 1: Repository klonen oder Dateien herunterladen

```bash
# Erstelle ein Verzeichnis für den MCP Server
mkdir -p ~/ha-mcp-server
cd ~/ha-mcp-server

# Kopiere alle Dateien hier hinein:
# - Dockerfile
# - docker-compose.yml
# - entrypoint.sh
# - .env.example
```

### Schritt 2: Umgebungsvariablen konfigurieren

```bash
# Kopiere das Beispiel
cp .env.example .env

# Bearbeite .env und setze deinen HA Config-Pfad
nano .env
```

Beispiel `.env` Inhalt:
```bash
# Für Docker Home Assistant
HA_CONFIG_PATH=/path/to/homeassistant/config

# Für Home Assistant OS (Supervised)
# HA_CONFIG_PATH=/usr/share/hassio/homeassistant

# Für lokales Testing
# HA_CONFIG_PATH=./test-config
```

### Schritt 3: Container starten

```bash
# Build und Start
docker-compose up -d

# Logs überprüfen
docker-compose logs -f
```

Der MCP Server läuft jetzt auf Port 3000.

## 🔧 Claude Desktop App konfigurieren

### Für Claude Desktop (empfohlen):

1. **Installiere Claude Desktop App** von https://claude.ai/download

2. **Konfiguriere den MCP Server:**

   Bearbeite die Claude Desktop Config-Datei:
   
   **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
   **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
   **Linux:** `~/.config/Claude/claude_desktop_config.json`

3. **Füge diese Konfiguration hinzu:**

```json
{
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
}
```

4. **Claude Desktop neu starten**

5. **Testen:** Öffne Claude Desktop und frage: "Kannst du meine Home Assistant Konfiguration sehen?"

## 🌐 Alternative: API Integration (Fortgeschritten)

Wenn du die Anthropic API direkt nutzen möchtest:

```python
import anthropic

client = anthropic.Anthropic(api_key="your-api-key")

# MCP Server Connection würde hier konfiguriert
# Details: https://docs.claude.com
```

## 📝 Verwendungsbeispiele

Sobald Claude mit deinem HA verbunden ist, kannst du z.B. fragen:

```
"Erstelle mir eine Automation, die bei Sonnenuntergang alle Außenlichter einschaltet"

"Analysiere meine bestehenden Automationen und schlage Optimierungen vor"

"Schreibe ein Script, das mein Haus in den Urlaubsmodus versetzt"

"Erstelle ein Lovelace Dashboard für meine Energieverwaltung"

"Finde Fehler in meiner configuration.yaml"
```

## 🔒 Sicherheitshinweise

### ⚠️ WICHTIG - Bitte beachten:

1. **Backups erstellen!**
   ```bash
   # Vor jeder Änderung durch Claude
   cp -r /path/to/homeassistant/config /path/to/backup/config-$(date +%Y%m%d)
   ```

2. **Git-Versionierung nutzen**
   ```bash
   cd /path/to/homeassistant/config
   git init
   git add .
   git commit -m "Initial commit vor MCP"
   ```

3. **Änderungen vor dem Reload überprüfen**
   - Lass Claude die Änderungen erklären
   - Prüfe die YAML-Syntax
   - Teste mit `ha core check`

4. **Read-Only Modus (optional)**
   
   Für extra Sicherheit kannst du den Container im Read-Only Modus starten:
   
   ```yaml
   # In docker-compose.yml
   volumes:
     - ${HA_CONFIG_PATH}:/config:ro  # :ro = read-only
   ```
   
   Dann kann Claude nur lesen, nicht schreiben. Du musst Änderungen manuell anwenden.

5. **Netzwerk-Isolation**
   - Der Container braucht KEINEN Internet-Zugang
   - Nur Claude Desktop braucht Zugriff zum Container

## 🐛 Troubleshooting

### Container startet nicht
```bash
# Logs prüfen
docker-compose logs

# Berechtigungen prüfen
ls -la /path/to/homeassistant/config

# Docker neu builden
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Claude kann keine Dateien sehen
```bash
# Prüfe ob Container läuft
docker ps | grep homeassistant-mcp

# Prüfe Volume-Mount
docker inspect homeassistant-mcp-server | grep Mounts -A 20

# Test-Datei im Container erstellen
docker exec homeassistant-mcp-server ls -la /config
```

### Home Assistant erkennt Änderungen nicht
```bash
# Home Assistant Config neu laden
# In HA: Entwicklerwerkzeuge -> YAML -> Alle YAML-Konfigurationen neu laden

# Oder via CLI
docker exec homeassistant ha core restart
```

## 🔄 Updates

```bash
# MCP Server aktualisieren
docker-compose pull
docker-compose down
docker-compose up -d

# Oder rebuild
docker-compose build --no-cache
docker-compose up -d
```

## 📊 Monitoring

```bash
# Logs live anschauen
docker-compose logs -f

# Resource-Nutzung
docker stats homeassistant-mcp-server

# Health Check
docker inspect homeassistant-mcp-server | grep Health -A 10
```

## 🛑 Deinstallation

```bash
# Container stoppen und entfernen
docker-compose down

# Volumes entfernen (optional)
docker-compose down -v

# Images entfernen (optional)
docker rmi ha-mcp-server_ha-mcp-server
```

## 💡 Tipps & Best Practices

1. **Teste zuerst mit einer Kopie:** Erstelle eine Kopie deiner HA-Config zum Testen
2. **Kleine Schritte:** Lass Claude jeweils nur eine Automation/Script erstellen
3. **Code Review:** Prüfe alle Änderungen vor dem Anwenden
4. **Backup-Strategie:** Automatische Backups vor Claude-Sessions
5. **Git-Workflow:** Commit nach jeder erfolgreichen Änderung

## 🔗 Weitere Ressourcen

- [MCP Dokumentation](https://modelcontextprotocol.io)
- [Home Assistant Docs](https://www.home-assistant.io/docs/)
- [Claude API Docs](https://docs.claude.com)
- [Docker Compose Docs](https://docs.docker.com/compose/)

## 📄 Lizenz

MIT License - Nutze es frei für deine Home Assistant Installation!

## 🤝 Support

Bei Problemen oder Fragen:
1. Prüfe die Logs: `docker-compose logs`
2. Überprüfe die Troubleshooting-Sektion oben
3. Erstelle ein Backup bevor du experimentierst!

---

**Viel Erfolg mit Claude + Home Assistant! 🏠🤖**
