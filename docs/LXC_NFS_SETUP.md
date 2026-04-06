# Namer auf Proxmox als Docker-LXC mit Host-NFS-Mount

## Zielbild

Dieses Setup folgt dem gleichen Grundprinzip wie dein StashApp-Projekt:

```text
QNAP NAS -> NFS-Mount auf dem Proxmox-Host -> Bind-Mount in den LXC -> Docker-Bind-Mount -> /media im Namer-Container
```

## Warum dieses Modell

- Die NAS wird nur **einmal auf dem Proxmox-Host** eingebunden.
- Der LXC bekommt nur ein normales Verzeichnis per `mp0`.
- Docker im LXC bindet dieses Verzeichnis nach `/media` in den Namer-Container.
- Das gleiche Muster kann später auch für StashApp genutzt werden.

## Wichtiger Unterschied zu einer VM

Namer arbeitet nicht nur lesend, sondern verschiebt Dateien aktiv zwischen:

- `watch`
- `work`
- `failed`
- `DESTINATION`

Darum ist das Rechtemodell wichtiger als bei einer reinen Medienbibliothek. In dieser LXC-Variante wird deshalb standardmäßig in `namer.cfg` gesetzt:

```ini
update_permissions_ownership = False
```

Das reduziert Probleme mit Besitz- und Rechtemanipulationen auf bind-gemounteten NAS-Pfaden.

## Empfohlene Reihenfolge

### 1. NFS auf dem Proxmox-Host mounten

Beispiel-Host-Pfad:

```text
/mnt/bindmounts/qnap-namer
```

Darunter sollten später diese Ordner vorhanden sein:

```text
/mnt/bindmounts/qnap-namer/watch
/mnt/bindmounts/qnap-namer/work
/mnt/bindmounts/qnap-namer/failed
/mnt/bindmounts/qnap-namer/DESTINATION
```

### 2. LXC vom Proxmox-Host aus erstellen

Nutze dieses Script direkt in der Proxmox-Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer-lxc.sh)"
```

Das Script:

- erstellt einen unprivilegierten Debian-LXC
- aktiviert `nesting=1,keyctl=1`
- bindet den Host-Pfad per `mp0` in den LXC ein
- installiert Docker im LXC
- erzeugt `docker-compose.yml` und `namer.cfg`
- startet Namer

### 3. Optional: standalone im Container ausführen

Falls du einen LXC schon hast, kannst du direkt im Container das standalone Script nutzen:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"
```

Standardpfad im Container:

```text
/mnt/namer-share
```

## Verwendete Pfade

### Host

```text
/mnt/bindmounts/qnap-namer
```

### LXC

```text
/mnt/namer-share
```

### Docker-Container

```text
/media
```

### Namer-Konfiguration

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
```

## Spätere gemeinsame Systemlösung mit StashApp

Empfohlenes Zielmodell:

- ein Host-seitiges NAS-Mount-Konzept
- pro Anwendung ein eigener Docker-LXC
- jede Anwendung mit eigenem standalone Installer im Container
- gleiche Verzeichnislogik und gleiche Proxmox-Bind-Mount-Strategie

So bleiben Namer und StashApp getrennt betreibbar, können später aber in einer übergreifenden Systemlösung zusammengeführt werden.
