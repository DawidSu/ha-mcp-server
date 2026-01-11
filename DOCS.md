# Claude MCP Server Addon

Dieses Addon stellt einen MCP (Model Context Protocol) Server bereit, der Claude direkten Zugriff auf deine Home Assistant Konfigurationsdateien ermöglicht.

## 🎯 Was kann Claude damit machen?

- ✅ Automationen erstellen und bearbeiten
- ✅ Scripts schreiben und anpassen  
- ✅ Szenen konfigurieren
- ✅ Lovelace UI Dashboards anpassen
- ✅ YAML-Konfigurationen optimieren
- ✅ Fehler in Configs finden und beheben
- ✅ Neue Integrationen konfigurieren

## 📋 Installation

### 1. Addon Repository hinzufügen

Füge diese URL zu deinen Home Assistant Addon Repositories hinzu:

```
https://github.com/DawidSu/ha-mcp-server
```

**So geht's:**
1. Gehe zu **Einstellungen** → **Add-ons** → **Add-on Store**
2. Klicke auf die drei Punkte (⋮) oben rechts
3. Wähle **Repositories**
4. Füge die URL hinzu und klicke **Hinzufügen**

### 2. Addon installieren

1. Suche nach "Claude MCP Server" im Add-on Store
2. Klicke auf **Installieren**
3. Warte bis die Installation abgeschlossen ist

### 3. Addon konfigurieren

#### Grundkonfiguration:
```yaml
ha_config_path: "/config"
log_level: "info"
enable_ssl: false
```

#### Erweiterte Optionen:
- **ha_config_path**: Pfad zur Home Assistant Konfiguration (normalerweise `/config`)
- **log_level**: Log-Level (`debug`, `info`, `warning`, `error`)
- **enable_ssl**: SSL aktivieren (für lokale Nutzung meist nicht nötig)

### 4. Addon starten

1. Klicke auf **Start** 
2. Aktiviere **Start on boot** wenn gewünscht
3. Überprüfe die Logs auf Fehler

## 🔧 Claude Desktop App konfigurieren

### Für Claude Desktop:

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
      "command": "nc",
      "args": [
        "localhost",
        "3000"
      ]
    }
  }
}
```

**Für Home Assistant OS/Supervised:**
```json
{
  "mcpServers": {
    "homeassistant": {
      "command": "nc", 
      "args": [
        "homeassistant.local",
        "3000"
      ]
    }
  }
}
```

4. **Claude Desktop neu starten**

5. **Testen:** Öffne Claude Desktop und frage: "Kannst du meine Home Assistant Konfiguration sehen?"

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

1. **Backups erstellen!** Erstelle vor jeder Änderung durch Claude ein Backup
2. **Git-Versionierung nutzen** für deine Home Assistant Konfiguration
3. **Änderungen überprüfen** vor dem Reload von Home Assistant
4. **Read-Only Modus** kann in der Addon-Konfiguration aktiviert werden

## 🐛 Troubleshooting

### Addon startet nicht
- Überprüfe die Logs im Home Assistant UI
- Stelle sicher, dass Port 3000 nicht anderweitig belegt ist

### Claude kann keine Dateien sehen  
- Überprüfe die Addon-Logs
- Stelle sicher, dass das Addon läuft (Status: Running)
- Teste die Verbindung: `nc homeassistant.local 3000`

### Home Assistant erkennt Änderungen nicht
- Lade die YAML-Konfiguration neu: **Entwicklerwerkzeuge** → **YAML** → **Alle YAML-Konfigurationen neu laden**

## 📊 Support

Bei Problemen:
1. Prüfe die Addon-Logs in Home Assistant
2. Überprüfe die Claude Desktop Logs  
3. Teste die Netzwerkverbindung
4. Erstelle ein Backup bevor du experimentierst!