# NamerAtProxmox

Namer auf Proxmox VE mit NAS-Freigabe im **Community-Scripts-Stil**.

Dieses Repository folgt jetzt demselben Grundmodell wie dein aktuelles **StashAtProxmox**-Projekt:

- NAS-Mount auf dem Proxmox-Host
- Bind-Mount in einen Docker-LXC
- Docker im LXC
- App-Installation im Container
- zusätzlicher Community-Scripts-artiger CT-Launcher mit dem bekannten Menü für **Default Install**, **Advanced Install**, **User Defaults** und **Settings**

## Empfohlene Architektur

```text
NAS -> Proxmox Host Mount -> LXC Bind Mount -> Docker Bind Mount -> /media
```

## Aktueller empfohlener Installationsweg

### Proxmox-Host-Skript im Community-Scripts-Stil

Empfohlenes Skript:

- `ct/namer-fixed.sh`

Start:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer-fixed.sh)"
```

Dieses Skript nutzt das Community-Scripts-Framework und ist deshalb für die CT-Erstellung die aktuell empfohlene Variante.

### Was du dabei bekommst

Beim Start über `ct/namer-fixed.sh` erscheint wieder die typische Community-Scripts-Oberfläche mit:

- **Default Install**
- **Advanced Install**
- **User Defaults**
- **Settings**

Damit werden typische CT-Werte wie diese nicht mehr manuell per Shell abgefragt, sondern über das gewohnte Menü gesetzt:

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

## Installer im Container

Für die eigentliche Namer-Einrichtung im Container gibt es jetzt zwei Varianten.

### Empfohlen zusammen mit `ct/namer-fixed.sh`

- `install/namer-install-community.sh`

Diese Variante ist für den Community-Scripts-artigen Ablauf gedacht.

### Bereits vorhandene standalone Variante

- `install/namer-install-standalone.sh`

Diese Variante bleibt weiterhin nutzbar, wenn du einen Container bereits hast und Namer direkt **im Container** einrichten willst.

Start dafür:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"
```

## Unterschied zwischen alter und neuer CT-Variante

### Ältere manuelle Variante

- `ct/namer-lxc.sh`

Dieses Skript fragt viele Werte direkt per `read -p` ab, zum Beispiel:

- CT ID
- Hostname
- Storage
- RAM
- CPU
- Host Bind Path
- Container Bind Path
- API Token

Das funktioniert zwar, wirkt aber **nicht wie ein typisches Community-Script**.

### Neue empfohlene Variante

- `ct/namer-fixed.sh`

Diese Version verhält sich deutlich näher an den offiziellen Community-Scripts:

- CT-Erstellung über das bekannte Menü
- App-Installation anschließend im Container
- klarere Trennung zwischen **Container-Erstellung** und **Anwendungs-Konfiguration**

## Wichtige Pfade

Standardmäßig wird dieses Modell verwendet:

- **Host:** eigener NAS-Mount auf dem Proxmox-Host, zum Beispiel `/mnt/bindmounts/qnap-namer`
- **LXC:** `/mnt/namer-share`
- **Docker-Container:** `/media`

Das bedeutet praktisch:

```text
Host-Mount            -> /mnt/bindmounts/qnap-namer
Bind-Mount im LXC     -> /mnt/namer-share
Docker-Mount in Namer -> /media
```

## Namer-Verzeichnisse

Namer arbeitet im Container standardmäßig mit diesen Pfaden:

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
```

Dafür sollten auf dem gemounteten NAS-Pfad diese Ordner vorhanden sein oder angelegt werden:

```text
watch
work
failed
DESTINATION
```

## Wichtiger Hinweis zu Rechten im LXC

Für die LXC-Variante ist standardmäßig gesetzt:

```ini
update_permissions_ownership = False
```

Das reduziert Rechteprobleme auf bind-gemounteten NAS-Pfaden, besonders bei **unprivilegierten LXCs**.

Gerade bei Namer ist das wichtig, weil Namer nicht nur liest, sondern aktiv mit diesen Verzeichnissen arbeitet:

- `watch`
- `work`
- `failed`
- `DESTINATION`

## Empfohlene Einstellungen im Community-Scripts-Menü

Für Namer im Docker-LXC sind in der Regel diese Werte sinnvoll:

- **Container Type:** Unprivileged
- **Nesting:** Yes
- **Keyctl:** Yes
- **Mknod:** No
- **Allow specific filesystem mounts:** No
- **Verbose mode:** No

## Wann welche Variante sinnvoll ist

### `ct/namer-fixed.sh`

Nutzen, wenn du:

- Namer neu auf Proxmox aufsetzen willst
- die gewohnte Community-Scripts-Menüführung möchtest
- CT-Werte bequem über **Default** oder **Advanced** setzen willst

### `install/namer-install-standalone.sh`

Nutzen, wenn du:

- bereits einen Debian-LXC oder eine andere Linux-Umgebung hast
- Docker dort direkt für Namer einrichten willst
- die App unabhängig vom CT-Ersteller testen möchtest

## Doku im Repository

- `docs/LXC_NFS_SETUP.md`
- `docs/SHARED_SYSTEM_MODEL.md`
- `config/namer.cfg.example`

## Aktueller Stand

Der aktuelle empfohlene Weg für neue Installationen ist also:

1. NAS auf dem Proxmox-Host mounten
2. `ct/namer-fixed.sh` starten
3. im Community-Scripts-Menü **Default** oder **Advanced Install** wählen
4. Namer danach im Container über den Installer einrichten lassen
5. Namer anschließend über die Weboberfläche auf Port `6980` nutzen
