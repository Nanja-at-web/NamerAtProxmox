# Namer auf Proxmox mit QNAP NAS

## Empfohlene Architektur

Die sauberste und am wenigsten fehleranfällige Variante ist:

- **Proxmox VM**
- **Debian 12 im Gast**
- **Docker im Gast**
- **QNAP-Freigabe per CIFS/SMB im Gast gemountet**
- **Namer als Docker-Container**

Warum diese Variante:

1. Namer bringt bereits ein Docker-Image mit.
2. Die vier Ordner (`watch`, `work`, `failed`, `DESTINATION`) lassen sich direkt unter einem gemeinsamen Mountpunkt bereitstellen.
3. SMB/CIFS-Mounts sind in einer normalen Linux-VM deutlich einfacher und robuster als in einer unprivilegierten LXC.
4. Die Community-Scripts-Welt ist grundsätzlich auf Debian-basierte Systeme ausgerichtet.

## Dein Ordnerlayout

Die NAS-Freigabe soll im Gast auf `/mnt/qnap/namer` gemountet werden.

Darunter liegen dann direkt:

- `/mnt/qnap/namer/watch`
- `/mnt/qnap/namer/work`
- `/mnt/qnap/namer/failed`
- `/mnt/qnap/namer/DESTINATION`

Im Container werden diese Pfade als `/media/...` verwendet:

- `watch_dir = /media/watch`
- `work_dir = /media/work`
- `failed_dir = /media/failed`
- `dest_dir = /media/DESTINATION`

## Installation im Debian-Gast

### 1. Debian 12 VM anlegen

Empfohlen:

- 2 vCPU
- 2 GB RAM
- 16-32 GB Disk
- Bridge: `vmbr0`

### 2. Installer ausführen

Sobald dein Repository öffentlich ist, kannst du den Installer direkt so starten:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-docker-vm.sh)"
```

Der Installer fragt interaktiv nach:

- QNAP-IP
- SMB-Freigabename
- SMB-Benutzer
- SMB-Passwort
- ThePornDB-API-Token
- Zeitzone
- PUID/PGID
- Web-Port

Danach werden automatisch eingerichtet:

- Docker
- CIFS-Mount
- Docker-Compose-Stack
- `namer.cfg`
- Containerstart

## Wichtige Dateien

- Installer: `install/namer-docker-vm.sh`
- Beispielkonfiguration: `config/namer.cfg.example`

## Hinweise

- Für einen einfachen `curl`-One-Liner muss das GitHub-Repository öffentlich erreichbar sein.
- Wenn du das Repository privat lässt, musst du das Skript manuell herunterladen oder mit Authentifizierung arbeiten.
- Die vier Namer-Ordner dürfen nicht ineinander verschachtelt sein.
- Wenn du die Weboberfläche nutzt, ist sie standardmäßig unter `http://<VM-IP>:6980/` erreichbar.
