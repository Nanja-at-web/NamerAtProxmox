# NamerAtProxmox

Create a Proxmox LXC for [Namer](https://github.com/ThePornDatabase/namer) and run the official Docker image:

```text
ghcr.io/theporndatabase/namer:latest
```

The script creates a Debian LXC, installs Docker inside it, and starts Namer as a systemd-managed Docker container. Namer works directly on the QNAP/NFS mount at `/namer`.

## Run from Proxmox

Run this on the Proxmox VE host as `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

With explicit options:

```bash
HOST_NAMER_PATH=/namer \
QNAP_IP=192.168.1.24 \
QNAP_EXPORT=/namer \
NAMER_PORT=6980 \
CTID=120 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

If the Proxmox host can write to `/namer` but the LXC cannot, create a privileged container for this NFS bind mount:

```bash
HOST_NAMER_PATH=/namer \
QNAP_IP=192.168.1.24 \
QNAP_EXPORT=/namer \
NAMER_PORT=6980 \
CT_UNPRIVILEGED=0 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

## QNAP NFS bind mount

Use NFS for this Linux/Proxmox setup. Your QNAP exports include `/namer`, so mount it on the Proxmox host before running the container script:

```bash
apt install -y nfs-common
mkdir -p /namer
showmount -e 192.168.1.24
mount -t nfs 192.168.1.24:/namer /namer
```

The script expects this mounted host path by default:

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

The script creates missing subfolders automatically after the NFS mount exists.

For a persistent mount, add this to `/etc/fstab` on the Proxmox host:

```fstab
192.168.1.24:/namer /namer nfs defaults,_netdev,nofail 0 0
```

Then test it:

```bash
mount -a
findmnt /namer
```

## NFS permissions

An unprivileged LXC maps container root to a high host UID, usually `100000`. QNAP may reject writes from that mapped UID even when Proxmox host root can write.

Test host access:

```bash
touch /namer/work/hosttest
rm /namer/work/hosttest
```

Test LXC access:

```bash
pct exec <CTID> -- touch /namer/work/testfile
pct exec <CTID> -- rm /namer/work/testfile
```

If host access works but LXC access fails, either adjust the QNAP NFS export mapping to allow the LXC mapped UID, or recreate the LXC with `CT_UNPRIVILEGED=0`.

## Paths

On the Proxmox host:

```text
/namer
```

Inside the LXC:

```text
/namer
```

Inside the Namer Docker container:

```text
/namer
/config
```

Generated Namer config:

```text
/opt/namer/config/namer.cfg
```

The generated config uses:

```text
watch_dir = /namer/watch
work_dir = /namer/work
failed_dir = /namer/faild
dest_dir = /namer/dest
web = True
port = 6980
host = 0.0.0.0
update_permissions_ownership = False
set_uid =
set_gid =
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
| `CT_UNPRIVILEGED` | `1` | Set `0` for a privileged LXC when QNAP NFS rejects unprivileged UID mappings |
| `HOST_NAMER_PATH` | `/namer` | Proxmox host path for QNAP NFS mount |
| `QNAP_IP` | `192.168.1.24` | QNAP IP used in error hints |
| `QNAP_EXPORT` | `/namer` | QNAP NFS export used in error hints |
| `NAMER_MEDIA_MOUNT` | `/namer` | Path used by Namer inside the Docker container |
| `NAMER_PORT` | `6980` | WebUI port |
| `PUID` | `99` | Namer Docker PUID |
| `PGID` | `100` | Namer Docker PGID |
| `UMASK` | `000` | Namer Docker UMASK |
| `FAILED_DIR_NAME` | `faild` | Failed folder name, matching your current layout |
| `DEST_DIR_NAME` | `dest` | Destination folder name |
| `CORES` | `2` | LXC CPU cores |
| `MEMORY` | `2048` | LXC RAM in MiB |
| `DISK_SIZE` | `8` | LXC root disk size in GiB |
