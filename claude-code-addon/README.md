# Claude Code Addon für Home Assistant

Ein vollwertiges **Claude Code Web-Interface** direkt in Home Assistant! Chatte mit Claude über eine moderne Web-Oberfläche und nutze dabei die volle Power des MCP (Model Context Protocol) Servers für direkten Zugriff auf deine Home Assistant Konfiguration.

## 🌟 Features

- **🤖 Claude Chat Interface** - Moderne Web-Oberfläche für Claude Conversations
- **🔗 MCP Integration** - Automatische Verbindung zum MCP Server für Dateizugriff  
- **🏠 Home Assistant Integration** - Läuft als Addon mit Ingress-Unterstützung
- **📱 Responsive Design** - Funktioniert auf Desktop, Tablet und Smartphone
- **⚡ Echtzeit-Features** - WebSocket-Verbindung für Live-Status
- **🛡️ Sicherheit** - Rate Limiting, Input Validation, Helmet Security Headers
- **🎨 Moderne UI** - Gradient-Design mit Glassmorphism-Effekten

## 📋 Installation

### 1. Voraussetzungen
- **Claude MCP Server Addon** muss installiert und aktiv sein
- **Anthropic API Key** (kostenlos bei anthropic.com)

### 2. Addon Installation
1. Füge das Repository zu Home Assistant hinzu
2. Installiere das "Claude Code CLI" Addon
3. Konfiguriere den Anthropic API Key
4. Starte das Addon

### 3. Konfiguration

```yaml
anthropic_api_key: "sk-ant-api03-..."  # Dein API Key von anthropic.com
model: "claude-3-5-sonnet-20241022"    # Claude Modell
max_tokens: 4096                       # Maximale Token pro Response  
auto_connect_mcp: true                 # Automatische MCP Verbindung
mcp_server_host: "localhost"           # MCP Server Host
mcp_server_port: 3000                  # MCP Server Port
log_level: "info"                      # Log Level
```

## 🚀 Nutzung

### Web-Interface
1. Öffne das Addon über **Home Assistant → Einstellungen → Add-ons → Claude Code CLI**
2. Klicke auf "OPEN WEB UI" oder nutze das Ingress-Interface
3. Beginne zu chatten!

### Beispiel-Prompts
```
"Zeige mir meine Home Assistant Konfiguration"
"Erstelle eine Automation für den Flur-Bewegungsmelder"  
"Analysiere meine Automationen auf Fehler"
"Schreibe ein Script für den Gute-Nacht-Modus"
"Optimiere meine configuration.yaml"
```

### Quick Actions
Das Interface bietet vorgefertigte Buttons für häufige Aufgaben:
- 📁 **Konfiguration anzeigen** 
- ⚡ **Automation erstellen**
- 🔍 **Fehlercheck**
- 🌙 **Script erstellen**

## 🔧 Erweiterte Konfiguration

### API Key erhalten
1. Gehe zu [anthropic.com](https://console.anthropic.com)
2. Erstelle einen Account 
3. Generiere einen API Key
4. Key beginnt mit `sk-ant-api03-...`

### MCP Server Verbindung
Das Addon verbindet sich automatisch mit dem Claude MCP Server:
- **Host**: `localhost` (Standard)
- **Port**: `3000` (Standard)
- **Auto-Connect**: `true` (Standard)

### Modell-Auswahl
Verfügbare Claude Modelle:
- `claude-3-5-sonnet-20241022` (Empfohlen - Balance aus Speed und Qualität)
- `claude-3-5-haiku-20241022` (Schnell und günstig)
- `claude-3-opus-20240229` (Höchste Qualität, langsamer)

## 🛡️ Sicherheit

- **Rate Limiting**: 10 Requests pro Minute pro IP
- **Input Validation**: Nachrichtenlänge und Format werden validiert
- **Helmet Security**: HTTP Security Headers aktiviert  
- **API Key Schutz**: Keys werden nicht in Logs angezeigt
- **CORS Schutz**: Nur erlaubte Origins können zugreifen

## 🔍 Troubleshooting

### Claude nicht verfügbar
```
Problem: "Claude ist nicht verfügbar"
Lösung: API Key in Addon-Einstellungen prüfen
```

### MCP Verbindung fehlgeschlagen  
```
Problem: "MCP server not reachable"
Lösung: Claude MCP Server Addon starten
```

### Performance-Probleme
```
Problem: Langsame Responses
Lösung: 
- Zu claude-3-5-haiku wechseln
- max_tokens reduzieren
- Conversation History kürzen
```

### Container startet nicht
```
bash
# Logs prüfen:
docker logs addon_local_claude-code-cli

# Häufige Ursachen:
- Ungültiger API Key Format
- Port 8080 bereits belegt
- Node.js Dependencies fehlen
```

## 📊 Status & Monitoring

Das Interface zeigt Live-Status an:
- **🟢 Claude**: Anthropic API verfügbar
- **🟢 MCP Server**: Verbindung zum MCP Server
- **Model Info**: Aktuell verwendetes Claude Modell

## 🔄 Updates

Das Addon updated sich automatisch über Home Assistant:
1. Neue Version wird in Add-ons angezeigt
2. "Update" Button klicken
3. Restart erfolgt automatisch

## 💡 Tipps & Tricks

### Effiziente Prompts
- **Spezifisch sein**: "Erstelle Automation für Küche" statt "Hilfe"
- **Kontext geben**: "Analysiere automation.yaml auf Syntaxfehler" 
- **Schrittweise**: Große Aufgaben in kleine Teile aufteilen

### Token sparen
- **Kurze Messages**: Lange Conversations verbrauchen mehr Token
- **Clear Context**: "Vergiss vorherige Conversation" für neue Themen
- **Haiku Model**: Für einfache Fragen claude-3-5-haiku nutzen

### Bessere Results
- **Beispiele geben**: "Erstelle Automation wie diese: [YAML]"
- **Format spezifizieren**: "Als YAML Code ausgeben"
- **Validation**: "Prüfe den Code auf Syntax-Fehler"

## 🆘 Support

Bei Problemen:
1. **Logs checken**: Home Assistant → Add-ons → Claude Code CLI → Logs
2. **Issue erstellen**: [GitHub Issues](https://github.com/DawidSu/ha-mcp-server/issues)
3. **Community**: Home Assistant Community Forum

---

**Viel Spaß mit Claude Code in Home Assistant! 🎉**