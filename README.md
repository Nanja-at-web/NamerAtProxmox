# NamerAtProxmox

Namer auf **Proxmox VE** mit Zugriff auf eine **QNAP NAS Freigabe**.

Dieses Repository stellt zwei Installationswege bereit:

1. **Empfohlen:** Proxmox-Host-Skript, das automatisch eine Debian-VM für Namer erstellt
2. **Alternativ:** Installer für eine bereits vorhandene Debian-VM

## Empfohlene Architektur

Die sauberste Lösung für dein Setup ist:

- **Proxmox VE**
- **Debian 12 VM**
- **Docker in der VM**
- **QNAP NAS per CIFS/SMB in der VM gemountet**
- **Namer als Docker-Container**

Warum diese Variante:

- Namer ist sehr gut für Docker geeignet
- SMB/CIFS-Mounts sind in einer VM einfacher als in einer LXC
- Rechte und Besitz lassen sich in einer normalen Linux-VM einfacher verwalten
- dein NAS-Ordnerlayout passt direkt zu Namers `/media/...`-Pfaden

## Verwendetes Ordnerlayout

Auf der QNAP-Freigabe liegen diese Ordner:

- `watch`
- `work`
- `failed`
- `DESTINATION`

Im Container werden sie so verwendet:

- `watch_dir = /media/watch`
- `work_dir = /media/work`
- `failed_dir = /media/failed`
- `dest_dir = /media/DESTINATION`

## Installer

### 1. Proxmox-Host-Installer

Datei:

- `install/proxmox-create-namer-vm.sh`

Dieser Weg ist für den gewünschten One-Click-Stil gedacht. Das Skript läuft direkt **auf dem Proxmox-Host** und:

- lädt ein Debian-12-Cloud-Image herunter
- erstellt automatisch eine VM
- richtet Cloud-Init ein
- installiert Docker im Gast
- bindet die QNAP-Freigabe im Gast ein
- schreibt `docker-compose.yml` und `namer.cfg`
- startet Namer automatisch

Start aus der Proxmox-Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/proxmox-create-namer-vm.sh)"
```

Weitere Details:

- `docs/PROXMOX_HOST_SETUP.md`

### 2. Installer für eine vorhandene Debian-VM

Datei:

- `install/namer-docker-vm.sh`

Dieses Skript läuft **in einer bestehenden Debian-VM** und richtet dort Docker, den CIFS-Mount, die Compose-Datei und die Namer-Konfiguration ein.

Start in der Debian-VM:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-docker-vm.sh)"
```

Weitere Details:

- `docs/SETUP.md`

## Beispielkonfiguration

Eine Beispielkonfiguration liegt hier:

- `config/namer.cfg.example`

## Voraussetzungen

Für beide Wege brauchst du:

- Proxmox VE oder eine Debian-VM auf Proxmox
- Zugriff auf deine QNAP-Freigabe
- SMB-Benutzername und Passwort
- einen **ThePornDB API Token**
- Internetzugang für Docker und Debian-Pakete

## Wichtiger Hinweis zum One-Liner

Der einfache `curl`-Aufruf funktioniert nur dann direkt, wenn dieses Repository **öffentlich** ist.

Wenn das Repository privat bleibt, musst du die Skripte manuell herunterladen oder mit Authentifizierung arbeiten.

## Ziel

Dieses Repository soll den Community-Scripts-ähnlichen Ablauf ermöglichen:

1. Skript per Web oder GitHub bereitstellen
2. Befehl kopieren
3. In Proxmox Shell oder Debian-VM einfügen
4. Interaktive Fragen beantworten
5. Namer startet mit NAS-Anbindung automatisch
