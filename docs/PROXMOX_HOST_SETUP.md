# Namer direkt vom Proxmox-Host aus bereitstellen

Dieses Setup orientiert sich am Community-Scripts-Prinzip:

1. Bash-Befehl kopieren
2. Im Proxmox-Shell ausführen
3. Interaktive Fragen beantworten
4. VM wird automatisch erstellt

## Was das Script macht

`install/proxmox-create-namer-vm.sh` läuft **auf dem Proxmox-Host** und erledigt folgende Schritte:

- Debian-12-Cloud-Image herunterladen
- neue VM mit `qm` anlegen
- Disk importieren
- Cloud-Init-User-Data erzeugen
- Debian-Gast automatisch konfigurieren
- Docker im Gast installieren
- QNAP-CIFS-Mount im Gast einrichten
- Namer-Container im Gast starten

## Voraussetzungen

- Proxmox VE Host
- funktionsfähige Internetverbindung
- Storage für VM-Disk, zum Beispiel `local-lvm`
- Storage mit Snippet-Support für Cloud-Init, typischerweise `local`
- QNAP-Freigabe `//IP/namer`
- ThePornDB API-Token

## Starten

Wenn das Repository öffentlich ist, kannst du das Script direkt aus der Proxmox-Shell starten:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/proxmox-create-namer-vm.sh)"
```

## Danach

Nach dem Start erzeugt das Script eine VM und bootet sie direkt. Im Debian-Gast werden dann automatisch eingerichtet:

- `/mnt/qnap/namer` als NAS-Mount
- `/mnt/qnap/namer/watch`
- `/mnt/qnap/namer/work`
- `/mnt/qnap/namer/failed`
- `/mnt/qnap/namer/DESTINATION`
- `/opt/namer/docker-compose.yml`
- `/opt/namer/config/namer.cfg`

Die Namer-Konfiguration verwendet im Container dann wie vorgesehen:

- `watch_dir = /media/watch`
- `work_dir = /media/work`
- `failed_dir = /media/failed`
- `dest_dir = /media/DESTINATION`

## Wichtiger Hinweis

Der einfache `curl`-One-Liner funktioniert nur, wenn das Repository öffentlich erreichbar ist. Falls das Repository privat bleibt, musst du das Script manuell auf den Proxmox-Host kopieren und dort ausführen.
