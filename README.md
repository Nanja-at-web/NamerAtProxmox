# NamerAtProxmox

Namer auf Proxmox VE mit NAS-Freigabe im Community-Scripts-Stil.

## Empfohlener Installer

Für neue Installationen ist jetzt der Community-Scripts-Installer empfohlen:

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
dest_dir = /media/DESTINATION
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
- `config/namer.cfg.example`
