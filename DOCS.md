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

#### Konfigurationsoptionen:
- **ha_config_path**: Pfad zur Home Assistant Konfiguration
  - Standard: `/config` (wird automatisch gemappt)
  - Normalerweise nicht ändern
- **log_level**: Detailgrad der Logs
  - `debug`: Sehr detailliert (für Entwicklung)
  - `info`: Standard-Informationen (empfohlen)
  - `warning`: Nur Warnungen und Fehler
  - `error`: Nur Fehler
- **enable_ssl**: SSL/TLS Verschlüsselung
  - `false`: Standard für lokale Nutzung
  - `true`: Nur wenn externe Zugriffe geplant sind

### 4. Addon starten

1. Klicke auf **Start**
2. Warte bis der Status auf "Running" wechselt (kann 1-2 Minuten dauern)
3. Aktiviere **Start on boot** für automatischen Start
4. Aktiviere **Watchdog** für automatischen Neustart bei Problemen
5. Überprüfe die Logs auf Fehler oder Warnungen

**Erfolgreiche Logs sollten zeigen:**
```
[INFO] Starting Claude MCP Server...
[INFO] Home Assistant Config Path: /config
[INFO] Starting MCP Filesystem Server on port 3000...
```

## 🔧 Claude Desktop App konfigurieren

### Für Claude Desktop:

1. **Installiere Claude Desktop App** von https://claude.ai/download

2. **Konfiguriere den MCP Server:**
   
   Bearbeite die Claude Desktop Config-Datei:
   
   **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`  
   **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`  
   **Linux:** `~/.config/Claude/claude_desktop_config.json`

3. **Füge diese Konfiguration hinzu:**

**Für lokale Home Assistant Installation:**
```json
{
  "mcpServers": {
    "homeassistant": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-stdio",
        "--",
        "nc",
        "localhost",
        "3000"
      ]
    }
  }
}
```

**Für Home Assistant OS/Supervised (Standard-Installation):**
```json
{
  "mcpServers": {
    "homeassistant": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-stdio",
        "--",
        "nc",
        "homeassistant.local",
        "3000"
      ]
    }
  }
}
```

**Alternative: Direkte TCP-Verbindung (falls obiges nicht funktioniert):**
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

5. **Verbindung testen:**
   - Öffne Claude Desktop
   - Warte bis die MCP-Verbindung aufgebaut ist (🔌 Symbol)
   - Teste mit: "Kannst du meine Home Assistant Konfiguration sehen?"
   - Claude sollte antworten und Dateien wie `configuration.yaml` erwähnen

### ⚠️ Häufige Verbindungsprobleme:

**Problem:** Claude zeigt keine MCP-Verbindung  
**Lösung:** 
- Prüfe ob das Addon läuft (Status: Running)
- Überprüfe die Addon-Logs auf Fehler
- Teste Netzwerkverbindung: `telnet homeassistant.local 3000`

**Problem:** "Connection refused" Fehler  
**Lösung:**
- Verwende die korrekte IP-Adresse deines Home Assistant
- Bei Docker: `docker inspect` für Container-IP
- Bei Proxmox/VM: LAN-IP der VM verwenden

**Problem:** MCP Server startet nicht  
**Lösung:**
- Prüfe verfügbaren Speicherplatz
- Starte das Addon neu
- Prüfe ob Port 3000 bereits belegt ist

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

### Installation schlägt fehl

**Error: "DockerError(403, 'denied')" oder "Can't install image"**  
**Ursache:** Home Assistant baut das Addon lokal und benötigt die Build-Dateien  
**Lösung:**
1. **Repository Reload:** **Add-on Store** → **⋮** → **Reload**
2. **Installation:** Das Addon wird beim ersten Installationsversuch lokal gebaut (dauert 5-10 Minuten)
3. **Geduld haben:** Der Build-Prozess läuft im Hintergrund
4. **Build-Status:** Prüfe `ha supervisor logs` für Build-Progress

**Error: "An unknown error occurred with addon..."**  
**Lösung:**
1. **Repository aktualisieren:** Gehe zu **Add-on Store** → **⋮** → **Reload**
2. **Cache löschen:** Neustart von Home Assistant
3. **Alternative:** Addon Repository entfernen und wieder hinzufügen
4. **Logs prüfen:** `ha supervisor logs` für Details

### Addon startet nicht
**Symptome:** Status bleibt auf "Stopped" oder "Error"  
**Lösungsschritte:**
1. Überprüfe die Logs: **Addon** → **Log** Tab
2. Häufige Ursachen:
   - Nicht genug RAM (mindestens 512MB freier Arbeitsspeicher)
   - Port 3000 bereits belegt
   - Filesystem-Berechtigungen
3. **Neustart versuchen:** Stop → Start
4. **Rebuild versuchen:** Deinstallieren → Neu installieren

### Claude kann keine Dateien sehen
**Symptome:** "Ich kann keine Konfigurationsdateien finden"  
**Diagnose:**
1. **Addon-Status prüfen:** Muss "Running" sein
2. **Logs überprüfen:** Sollte keine Fehler zeigen
3. **Netzwerk testen:** 
   ```bash
   # Von einem anderen Gerät im Netzwerk:
   telnet homeassistant.local 3000
   # Sollte Verbindung aufbauen
   ```
4. **Claude Desktop Config prüfen:** JSON-Syntax korrekt?
5. **Claude Desktop neu starten** nach Config-Änderungen

### Home Assistant erkennt Änderungen nicht
**Nach Claude-Änderungen:**
1. **YAML neu laden:** **Entwicklerwerkzeuge** → **YAML** → **Alle YAML-Konfigurationen neu laden**
2. **Bei Fehlern:** Prüfe YAML-Syntax mit **Konfiguration überprüfen**
3. **Vollständiger Neustart:** Falls nötig über **Entwicklerwerkzeuge** → **Neu starten**

### Performance-Probleme
**Addon läuft langsam:**
- Erhöhe RAM-Limit in Addon-Konfiguration
- Reduziere Log-Level auf "warning" oder "error"
- Überwache Ressourcenverbrauch im Supervisor

### Firewall/Netzwerk-Probleme
**Verbindung von außen funktioniert nicht:**
- Port 3000 ist nur für lokale Verbindungen gedacht
- Für externe Zugriffe: VPN verwenden, nicht Port-Forwarding
- Bei Docker: Host-Netzwerk-Modus überprüfen

## 📊 Support

Bei Problemen:
1. Prüfe die Addon-Logs in Home Assistant
2. Überprüfe die Claude Desktop Logs  
3. Teste die Netzwerkverbindung
4. Erstelle ein Backup bevor du experimentierst!