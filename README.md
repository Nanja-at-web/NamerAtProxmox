# NamerAtProxmox

Namer auf Proxmox VE mit NAS-Freigabe im Community-Scripts-Stil.

## Empfohlener Installer auf `main`

Für neue Installationen auf `main` ist aktuell dieser Installer dokumentiert:

- `ct/namer.sh`

Start:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

Dieser Installer nutzt das Community-Scripts-Framework und zeigt das bekannte Menü mit:

- `Default Install`
- `Advanced Install`
- `User Defaults`
- `App Defaults for Namer`
- `Settings`

## Repository-native Planungsdokumente

Damit das Projekt auch ohne alte Chat-Anhänge oder abgelaufene Uploads verständlich bleibt, ist der aktuelle technische Zielzustand direkt im Repo dokumentiert.

Wichtige Dateien dafür:

- `STATUS.md`
- `CHANGELOG.md`
- `docs/VARIANT_B_IMPLEMENTATION_PLAN.md`

`docs/VARIANT_B_IMPLEMENTATION_PLAN.md` ist die technische Source of Truth für die laufende Variant-B-Migration auf dem Test-Branch.

## Test-Branch: autonomer NFS-v1-Installer

Auf dem Test-Branch `test/nfs-v1-autark-installer` gibt es einen erweiterten Teststand mit:

- integriertem NFS-v1-Host-Mount
- Bind-Mount in den LXC
- eingebettetem CT-Installer
- ThePornDB-Token-Abfrage
- Docker-Healthcheck

Start des Teststands:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/test/nfs-v1-autark-installer/ct/namer.sh)"
```

## Konkreter Testplan für deine QNAP-NFS-Freigabe

### Voraussetzungen

Vor dem Test sollte gelten:

- QNAP exportiert die NFS-Freigabe korrekt
- Exportpfad ist `/namer`
- in der Freigabe sind diese Ordner vorhanden oder dürfen automatisch erstellt werden:
  - `watch`
  - `work`
  - `failed`
  - `dest`
- auf Proxmox wird ein freier Test-CT verwendet
- für den ersten Test sollte **kein produktiver Container** verwendet werden

### Startbefehl auf Proxmox

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/test/nfs-v1-autark-installer/ct/namer.sh)"
```

### Empfohlene Antworten während des Tests

Verwende beim ersten Test am besten diese Werte:

- `NAS host/IP:`
  - **deine QNAP-IP**
  - Beispiel: `192.168.1.50`
- `NAS export path (example: /namer):`
  - `/namer`
- `Host mount path [/mnt/bindmounts/qnap-namer]:`
  - `/mnt/bindmounts/qnap-namer-test`
- `Container mount path [/mnt/namer-share]:`
  - `/mnt/namer-share`
- `Create watch/work/failed/dest automatically? [true]:`
  - `true`
- `Write persistent /etc/fstab entry on Proxmox host? [false]:`
  - `false`
- `Run optional write test after bind mount? [false]:`
  - `true`
- `Additional NFS mount options [empty]:`
  - leer lassen beim ersten Test

Danach folgt auf dem Proxmox-Host die ThePornDB-Token-Abfrage:

- `ThePornDB API token:`
  - hier den gültigen Token einfügen
  - die Eingabe bleibt verborgen

### Warum diese Testwerte empfohlen sind

Für den ersten Test ist diese Kombination am sichersten:

- separater Host-Mountpfad: `/mnt/bindmounts/qnap-namer-test`
- kein permanenter `/etc/fstab`-Eintrag
- Write-Test aktiviert

So wird geprüft:

- NFS-Mount funktioniert
- der LXC sieht den Bind-Mount
- Lesen und Schreiben funktionieren
- die Host-Boot-Konfiguration wird noch nicht dauerhaft verändert

## Prüfen nach der Installation

Nach erfolgreichem Lauf auf dem Proxmox-Host prüfen:

```bash
pct config <CTID>
pct exec <CTID> -- bash -lc 'mount | grep namer-share || true'
pct exec <CTID> -- bash -lc 'ls -lah /mnt/namer-share'
pct exec <CTID> -- bash -lc 'docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
pct exec <CTID> -- bash -lc 'docker logs --tail 100 namer'
```

Dann die Web-UI im Browser öffnen:

```text
http://<CT-IP>:6980
```

## Alternative Host-Variante

Zusätzlich gibt es weiterhin die direkte Host-Variante ohne Community-Menü:

- `ct/namer-lxc.sh`

Diese Variante ist eher für manuelle Tests oder Spezialfälle gedacht.

## Installer im Container

Für bestehende Container gibt es den standalone Installer:

- `install/namer-install-standalone.sh`

Start im Container:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"
```

## Architektur

```text
NAS -> Proxmox Host Mount -> LXC Bind Mount -> Docker Bind Mount -> /media
```

## Standardpfade

- Host: `/mnt/bindmounts/qnap-namer`
- LXC: `/mnt/namer-share`
- Container: `/media`

## Namer-Verzeichnisse

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/dest
```

## Hinweis zu Rechten

Im LXC-Setup ist standardmäßig gesetzt:

```ini
update_permissions_ownership = False
```

Das reduziert Rechteprobleme auf bind-gemounteten NAS-Pfaden.

## Weitere Dateien

- `README_LXC.md`
- `docs/LXC_NFS_SETUP.md`
- `docs/SHARED_SYSTEM_MODEL.md`
- `docs/VARIANT_B_IMPLEMENTATION_PLAN.md`
- `config/namer.cfg.example`
