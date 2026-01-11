# 🚀 Quick Start Guide

## Installation in 3 Schritten:

### 1️⃣ Setup ausführen
```bash
chmod +x setup.sh
./setup.sh
```

Das Setup-Script führt dich durch:
- Prüfung der Voraussetzungen
- Konfiguration des HA-Pfads
- Backup-Erstellung
- Container-Start
- Claude Desktop Konfiguration

### 2️⃣ Claude Desktop App installieren
- Download: https://claude.ai/download
- Installieren und öffnen
- Das Setup-Script hat die Config bereits erstellt

### 3️⃣ Testen
Öffne Claude Desktop und frage:
```
Kannst du meine Home Assistant Konfiguration sehen?
Zeige mir welche Automationen ich habe.
```

## ⚡ Manuelle Installation

Falls du das Setup-Script nicht nutzen möchtest:

```bash
# 1. .env erstellen
cp .env.example .env
nano .env  # HA_CONFIG_PATH anpassen

# 2. Container starten
docker-compose up -d

# 3. Claude Desktop Config erstellen
# Siehe README.md Abschnitt "Claude Desktop App konfigurieren"
```

## 🎯 Was kann ich mit Claude machen?

Beispiel-Anfragen:

```
"Erstelle eine Automation für Bewegungsmelder im Flur"

"Analysiere meine configuration.yaml und finde Verbesserungen"

"Schreibe ein Script für den Gute-Nacht-Modus"

"Erstelle ein Dashboard für meine Stromkosten"

"Zeige mir alle Fehler in meinen Automationen"
```

## 📋 Checkliste vor dem Start

- [ ] Docker installiert
- [ ] Home Assistant Config-Pfad bekannt
- [ ] Backup erstellt
- [ ] Git-Versionierung aktiviert (empfohlen)
- [ ] Container läuft (`docker ps`)
- [ ] Claude Desktop installiert
- [ ] Claude Desktop Config erstellt

## 🆘 Hilfe

Problem? Siehe README.md Abschnitt "Troubleshooting"

Container-Status prüfen:
```bash
docker-compose logs -f
```

---

**Bereit? Los geht's! 🎉**
