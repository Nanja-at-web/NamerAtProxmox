# NamerAtProxmox

Namer auf Proxmox VE mit NAS-Freigabe.

Dieses Repository folgt jetzt demselben Grundmodell wie dein Stash-Projekt:

- NAS-Mount auf dem Proxmox-Host
- Bind-Mount in einen Docker-LXC
- Docker im LXC
- standalone Installationsskript im Container

## Empfohlene Architektur

```text
NAS -> Proxmox Host Mount -> LXC Bind Mount -> Docker Bind Mount -> /media
```

## Installer

### Proxmox-Host-Skript

- `ct/namer-lxc.sh`

Start:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer-lxc.sh)"
```

### standalone Installer im LXC

- `install/namer-install-standalone.sh`

Start:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"
```

## Wichtige Pfade

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

## Wichtiger Hinweis

Für die LXC-Variante ist standardmäßig gesetzt:

```ini
update_permissions_ownership = False
```

Das reduziert Rechteprobleme auf bind-gemounteten NAS-Pfaden.

## Doku

- `docs/LXC_NFS_SETUP.md`
- `docs/SHARED_SYSTEM_MODEL.md`
- `config/namer.cfg.example`
