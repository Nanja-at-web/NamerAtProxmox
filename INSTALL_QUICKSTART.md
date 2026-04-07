# Namer auf Proxmox – Schnellstart

## Empfohlene Variante

Für dein Setup ist **ein Debian 13 Docker-LXC unter Proxmox** die beste Wahl.

Warum:

- weniger Overhead als eine VM
- einfacher Zugriff auf die NAS-Freigabe über **Host-Mount + LXC-Bind-Mount**
- passt gut zum Community-Scripts-Stil
- Docker-Image von Namer ist offiziell dokumentiert

## Zielaufbau

```text
QNAP NAS -> Proxmox Host Mount -> LXC Bind Mount -> Docker Bind Mount -> /media
```

## Deine Namer-Ordner

Im Container sollen diese Pfade verwendet werden:

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
```

## 1. NAS-Freigabe auf dem Proxmox-Host mounten

Beispiel Host-Pfad:

```bash
mkdir -p /mnt/bindmounts/qnap-namer
```

Wenn deine Freigabe wirklich per NFS exportiert ist:

```bash
mount -t nfs <NAS-IP>:/namer /mnt/bindmounts/qnap-namer
```

Wenn du SMB/CIFS nutzt, musst du stattdessen einen CIFS-Mount verwenden.

Auf dem Host müssen danach diese Ordner sichtbar sein:

```text
/mnt/bindmounts/qnap-namer/watch
/mnt/bindmounts/qnap-namer/work
/mnt/bindmounts/qnap-namer/failed
/mnt/bindmounts/qnap-namer/DESTINATION
```

## 2. Community-Scripts-ähnlichen CT-Installer starten

In der Proxmox-Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer-fixed.sh)"
```

Das Script erstellt einen Docker-fähigen Debian-LXC und startet danach automatisch den Installer im Container.

## 3. NAS-Freigabe in den LXC durchreichen

Nach dem Erstellen des Containers den CT anhalten und in `/etc/pve/lxc/<CTID>.conf` ergänzen:

```ini
mp0: /mnt/bindmounts/qnap-namer,mp=/mnt/namer-share
```

Danach den Container wieder starten.

## 4. Installer im Container

Der Container-Installer richtet automatisch ein:

- Docker
- `/opt/namer/.env`
- `/opt/namer/docker-compose.yml`
- `/opt/namer/config/namer.cfg`
- die Verzeichnisse unterhalb des Media-Roots

Die Konfiguration ist so ausgelegt, dass Namer intern mit `/media/...` arbeitet.

## 5. ThePornDB-Token setzen

Datei:

```text
/opt/namer/config/namer.cfg
```

Dort den Wert setzen:

```ini
porndb_token = DEIN_TOKEN
```

## 6. Wichtig bei NAS + unprivileged LXC

In der Beispielkonfiguration ist absichtlich gesetzt:

```ini
update_permissions_ownership = False
```

Das vermeidet Probleme, wenn Namer auf bind-gemounteten NAS-Pfaden läuft.

## WebUI

Standard:

```text
http://<LXC-IP>:6980
```

## Falls du bereits einen LXC hast

Dann im bestehenden Container direkt ausführen:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"
```
