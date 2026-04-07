# Proxmox Host Mount und LXC Bind-Mount für Namer

Diese Anleitung ergänzt den Installer `ct/namer.sh`.

Der Installer richtet den Debian-LXC und Namer im Container ein. Damit Namer aber auf die QNAP-Freigabe zugreifen kann, muss die NAS-Freigabe zuerst auf dem **Proxmox-Host** gemountet und danach in den LXC **bind-gemountet** werden.

## Empfohlenes Modell

```text
QNAP NAS -> Proxmox Host Mount -> LXC Bind Mount -> Docker Bind Mount -> /media
```

## 1. NAS auf dem Proxmox-Host mounten

### Variante A: NFS

Wenn deine Freigabe als `IP:/namer` exportiert wird, ist NFS meist die passende Methode.

```bash
apt-get update
apt-get install -y nfs-common
mkdir -p /mnt/bindmounts/qnap-namer
mount -t nfs <QNAP_IP>:/namer /mnt/bindmounts/qnap-namer
```

Persistenter Eintrag in `/etc/fstab`:

```fstab
<QNAP_IP>:/namer /mnt/bindmounts/qnap-namer nfs defaults,_netdev 0 0
```

### Variante B: SMB/CIFS

Falls deine QNAP-Freigabe per SMB bereitgestellt wird:

```bash
apt-get update
apt-get install -y cifs-utils
mkdir -p /mnt/bindmounts/qnap-namer
mount -t cifs //<QNAP_IP>/namer /mnt/bindmounts/qnap-namer \
  -o username=<USER>,password=<PASS>,iocharset=utf8,vers=3.0
```

Persistenter Eintrag in `/etc/fstab`:

```fstab
//<QNAP_IP>/namer /mnt/bindmounts/qnap-namer cifs username=<USER>,password=<PASS>,iocharset=utf8,vers=3.0,_netdev,nofail 0 0
```

## 2. Ordner prüfen

Auf dem Host müssen diese Ordner verfügbar sein:

```text
/mnt/bindmounts/qnap-namer/watch
/mnt/bindmounts/qnap-namer/work
/mnt/bindmounts/qnap-namer/failed
/mnt/bindmounts/qnap-namer/DESTINATION
```

## 3. LXC mit Installer erzeugen

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

## 4. Bind-Mount in den LXC eintragen

Ermittle die CTID und ergänze auf dem Proxmox-Host die Container-Konfiguration:

```bash
nano /etc/pve/lxc/<CTID>.conf
```

Eintrag ergänzen:

```ini
mp0: /mnt/bindmounts/qnap-namer,mp=/mnt/namer-share
```

## 5. Container neu starten

```bash
pct restart <CTID>
```

## 6. Im LXC prüfen

```bash
pct exec <CTID> -- ls -la /mnt/namer-share
```

Danach bindet Docker im LXC automatisch:

```text
/mnt/namer-share -> /media
```

## 7. Namer-Pfade

Die Namer-Konfiguration bleibt dann:

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
```

## Hinweis zu Rechten

Empfohlen für dieses Setup:

```ini
update_permissions_ownership = False
```

So vermeidest du Probleme mit Besitz- und Rechteänderungen auf NAS-Pfaden.
