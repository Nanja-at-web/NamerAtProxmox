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

## Aktuell empfohlene Reihenfolge

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

Nutze jetzt bevorzugt dieses Script direkt in der Proxmox-Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer-fixed.sh)"
```

Dieses Skript ist auf das Community-Scripts-Framework aufgebaut und zeigt beim Start das bekannte Menü mit:

- **Default Install**
- **Advanced Install**
- **User Defaults**
- **Settings**

Damit werden typische CT-Werte wie diese über das Menü gesetzt und nicht mehr direkt per `read -p` abgefragt:

- CT ID
- Hostname
- CPU
- RAM
- Disk
- Unprivileged / Privileged
- Nesting
- Keyctl
- Netzwerk
- Storage

Das Script:

- erstellt einen unprivilegierten Debian-LXC
- aktiviert die typischen Docker-LXC-Funktionen über die Community-Scripts-Logik
- startet danach automatisch den **Community-Installer** im Container
- startet Docker und Namer im Container

### 3. Automatisch gestarteter Installer im Container

Für den Community-Scripts-artigen Ablauf ist jetzt dieser Installer zuständig:

```text
install/namer-install-community.sh
```

Er wird normalerweise **nicht manuell aufgerufen**, sondern von `ct/namer-fixed.sh` nach der CT-Erstellung automatisch im Container gestartet.

Er richtet im Container ein:

- Docker
- `/opt/namer/.env`
- `/opt/namer/docker-compose.yml`
- `/opt/namer/config/namer.cfg`
- die Verzeichnisse unterhalb des Media-Roots

### 4. Manuell ausführbare Direkt-Variante

Falls du einen LXC schon hast, kannst du weiterhin direkt im Container das standalone Script nutzen:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"
```

Diese Variante ist die **manuelle Direktinstallation** und nicht der automatisch vom CT-Launcher verwendete Standardweg.

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

## Empfohlene LXC-Einstellungen

Für Namer im Docker-LXC sind typischerweise diese Werte sinnvoll:

- **Container Type:** Unprivileged
- **Nesting:** Yes
- **Keyctl:** Yes
- **Mknod:** No
- **Allow specific filesystem mounts:** No
- **Verbose mode:** No

## Unterschied zwischen alter und neuer CT-Variante

### Ältere manuelle Variante

```text
ct/namer-lxc.sh
```

Diese Variante fragt viele Werte per Shell ab und verhält sich nicht wie ein typisches Community-Script.

### Neue empfohlene Variante

```text
ct/namer-fixed.sh
```

Diese Version trennt sauber zwischen:

- **Container-Erstellung über das Community-Scripts-Menü**
- **automatisch gestartetem Community-Installer im Container**

Dadurch entspricht die Bedienung deutlich stärker dem Modell von `StashAtProxmox`.

## Spätere gemeinsame Systemlösung mit StashApp

Empfohlenes Zielmodell:

- ein Host-seitiges NAS-Mount-Konzept
- pro Anwendung ein eigener Docker-LXC
- jede Anwendung mit eigenem Installer im Container
- gleiche Verzeichnislogik und gleiche Proxmox-Bind-Mount-Strategie

So bleiben Namer und StashApp getrennt betreibbar, können später aber in einer übergreifenden Systemlösung zusammengeführt werden.
