# Namer auf Proxmox mit QNAP TS-210

Diese Anleitung beschreibt den empfohlenen Aufbau für **Namer** auf **Proxmox VE** mit einer **QNAP TS-210** als Datenspeicher.

## Empfohlene Architektur

```text
QNAP TS-210 (NFS) -> Proxmox Host Mount -> unprivilegierter Debian LXC -> Docker -> Namer
```

## Warum dieser Aufbau sinnvoll ist

- Die NAS-Freigabe wird nur **einmal** auf dem Proxmox-Host eingebunden.
- Proxmox reicht den Host-Pfad per **Bind-Mount** in den LXC weiter.
- Namer bekommt im Docker-Container nur einen einzigen klaren Pfad: `/media`.
- Änderungen an der NAS-Anbindung betreffen nur den Host-Mount und nicht die Docker-Compose-Datei.

## Empfohlener Host-Typ

Für Namer ist unter Proxmox in der Regel dies der beste Weg:

1. **Linux LXC**
2. **unprivilegiert**
3. **Docker im LXC**
4. **NAS auf dem Proxmox-Host mounten**
5. **Bind-Mount in den LXC**

Nicht empfohlen als Standard:

- **Windows**: unnötig schwerer für NAS-Mount, Docker und Linux-Dateirechte.
- **volle Docker-VM**: funktioniert, braucht aber mehr RAM, CPU und Pflege.
- **Docker direkt auf dem Proxmox-Host**: technisch möglich, aber schlechter getrennt als ein eigener LXC.

## Warum NFS bevorzugt ist

Bei einer QNAP TS-210 mit Proxmox/Linux ist **NFS** meistens die sauberste Wahl.

Vorteile:

- passt gut zu Linux und Proxmox
- einfacher Host-Mount
- einfacher Bind-Mount in den LXC
- weniger SMB/CIFS-Sonderfälle bei Rechten

Wenn NFS bei deiner Freigabe nicht sinnvoll nutzbar ist, kannst du stattdessen SMB/CIFS auf dem **Proxmox-Host** mounten und denselben weiteren Aufbau beibehalten.

## Zielpfade

### Auf der QNAP-Freigabe

Freigabe:

```text
<nas-ip>:/namer
```

Erwartete Ordner:

```text
watch
work
failed
DESTINATION
```

### Auf dem Proxmox-Host

Empfohlener Mountpunkt:

```text
/mnt/bindmounts/qnap-namer
```

### Im LXC

Empfohlener Bind-Mount:

```text
/mnt/namer-share
```

### Im Docker-Container

Namer sieht denselben Inhalt unter:

```text
/media
```

Daraus ergeben sich in `namer.cfg` die Pfade:

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
```

## QNAP vorbereiten

### NFS aktivieren

In QNAP QTS:

1. **Control Panel** öffnen
2. **Network & File Services**
3. **Win/Mac/NFS**
4. **NFS Service** aktivieren
5. NFS-Zugriff für die Freigabe `namer` für die IP deines Proxmox-Hosts erlauben

## Proxmox-Host vorbereiten

### Mountpunkt anlegen

```bash
mkdir -p /mnt/bindmounts/qnap-namer
```

### Testweise per NFS mounten

```bash
mount -t nfs <QNAP-IP>:/namer /mnt/bindmounts/qnap-namer
```

### Prüfen

```bash
ls -la /mnt/bindmounts/qnap-namer
```

Du solltest dort deine Ordner `watch`, `work`, `failed` und `DESTINATION` sehen.

### Dauerhaft in `/etc/fstab`

Beispiel:

```fstab
<QNAP-IP>:/namer /mnt/bindmounts/qnap-namer nfs defaults,_netdev 0 0
```

## Namer-LXC installieren

Empfohlenes Script aus diesem Repository:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer-fixed.sh)"
```

Empfohlene Werte im Community-Scripts-Menü:

- Debian 13
- unprivilegierter LXC
- 2 vCPU
- 2048 MB RAM
- 8 GB Disk
- Nesting aktiv
- Keyctl aktiv

## Bind-Mount in den LXC setzen

Beispiel mit CTID `123`:

```bash
pct set 123 -mp0 /mnt/bindmounts/qnap-namer,mp=/mnt/namer-share
```

Danach den Container einmal neu starten:

```bash
pct restart 123
```

## Im LXC prüfen

```bash
pct exec 123 -- ls -la /mnt/namer-share
```

## Namer-Konfiguration

Die Installer-Dateien in diesem Repository legen Namer unter `/opt/namer` ab.

Wichtige Dateien:

```text
/opt/namer/docker-compose.yml
/opt/namer/.env
/opt/namer/config/namer.cfg
```

Wichtig in `namer.cfg`:

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
web = True
port = 6980
host = 0.0.0.0
```

Außerdem musst du deinen **ThePornDB API Token** setzen:

```ini
porndb_token = DEIN_TOKEN
```

## Warum `update_permissions_ownership = False` sinnvoll ist

Bei einem unprivilegierten LXC können Bind-Mounts sonst leicht Rechteprobleme verursachen. Für eine NAS-Freigabe ist es daher sinnvoll, standardmäßig keine Eigentümer-/Rechte-Umschreibungen durch Namer auf dem Zielpfad zu erzwingen.

Empfohlen:

```ini
update_permissions_ownership = False
```

## Weboberfläche

Nach erfolgreicher Installation ist Namer normalerweise erreichbar unter:

```text
http://<LXC-IP>:6980
```

## Schnelltest

1. Datei nach `/watch` kopieren
2. beobachten, ob sie nach `/work` wandert
3. bei Erfolg nach `/DESTINATION`
4. bei Fehlschlag nach `/failed`

## Wenn du SMB/CIFS statt NFS nutzen willst

Dann bleibt der Aufbau gleich. Nur der Host-Mount ändert sich.

Prinzip:

```text
QNAP SMB Share -> Proxmox Host CIFS Mount -> Bind-Mount in LXC -> Docker -> /media
```

Für Linux/Proxmox bleibt NFS aber meist die angenehmere Standardlösung.
