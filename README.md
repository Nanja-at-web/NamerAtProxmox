# NamerAtProxmox

Create a Proxmox LXC for [Namer](https://github.com/ThePornDatabase/namer) and run the official Docker image:

```text
ghcr.io/theporndatabase/namer:latest
```

The script creates a Debian LXC, installs Docker inside it, and starts Namer as a systemd-managed Docker container.

## Run from Proxmox

Run this on the Proxmox VE host as `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

With explicit options:

```bash
HOST_NAMER_PATH=/namer \
QNAP_IP=192.168.1.24 \
NAMER_PORT=6980 \
CTID=120 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

## QNAP bind mount

The script expects the QNAP share to already be mounted on the Proxmox host. Default source path:

```text
/namer
```

Default folder layout:

```text
/namer/watch
/namer/work
/namer/faild
/namer/dest
```

Example QNAP mount on the Proxmox host:

```bash
mkdir -p /namer
apt install -y cifs-utils
mount -t cifs //192.168.1.24/namer /namer \
  -o username=YOUR_USER,password=YOUR_PASSWORD,uid=100099,gid=100100,iocharset=utf8,noperm
```

Why `uid=100099,gid=100100`? The LXC is unprivileged. Namer runs with `PUID=99` and `PGID=100`, which map to host IDs `100099` and `100100`.

For a persistent mount, add an `/etc/fstab` entry on the Proxmox host and store credentials in a root-readable credentials file.

## Paths

Inside the LXC:

```text
/namer
```

Inside the Namer Docker container:

```text
/media
/config
```

Generated Namer config:

```text
/opt/namer/config/namer.cfg
```

The generated config uses:

```text
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/faild
dest_dir = /media/dest
web = True
port = 6980
host = 0.0.0.0
```

After install, edit the TPDB API token:

```bash
pct exec <CTID> -- nano /opt/namer/config/namer.cfg
```

Set:

```text
porndb_token = YOUR_TOKEN
```

Then restart Namer:

```bash
pct exec <CTID> -- systemctl restart namer
```

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `CTID` | next available | Proxmox container ID |
| `CT_HOSTNAME` | `namer` | LXC hostname |
| `HOST_NAMER_PATH` | `/namer` | Proxmox host path for QNAP share |
| `QNAP_IP` | `192.168.1.24` | Informational QNAP IP used in error hints |
| `NAMER_PORT` | `6980` | WebUI port |
| `PUID` | `99` | Namer Docker PUID |
| `PGID` | `100` | Namer Docker PGID |
| `UMASK` | `000` | Namer Docker UMASK |
| `FAILED_DIR_NAME` | `faild` | Failed folder name, matching your current layout |
| `DEST_DIR_NAME` | `dest` | Destination folder name |
| `CORES` | `2` | LXC CPU cores |
| `MEMORY` | `2048` | LXC RAM in MiB |
| `DISK_SIZE` | `8` | LXC root disk size in GiB |
