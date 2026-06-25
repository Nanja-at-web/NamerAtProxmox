# NamerAtProxmox

Create a Proxmox LXC for [Namer](https://github.com/ThePornDatabase/namer).

By default this installer builds and runs the configured Nanja-at-web Namer branch:

```text
Nanja-at-web/namer@codex/matching-cleanup-review-db
```

The script creates a Debian LXC, installs Docker inside it, builds the selected Namer branch as a local Docker image, and starts Namer as a systemd-managed Docker container. Namer works directly on the QNAP/NFS mount at `/namer`.

The installer keeps the Proxmox console quiet by default. Detailed `apt`, `pct`, `git`, and Docker build output is written to log files and shown only when something fails.
When run from an interactive Proxmox shell, the entry script opens a Proxmox VE Helper-Scripts-style menu with `Default Install` and `Advanced Install`.
The source install builds a local Docker image and can take several minutes; the Docker build output is streamed to the console and log so the install no longer appears stuck at `Installing Namer`.

## Run from Proxmox

Run this on the Proxmox VE host as `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

To skip the menu and force the default path:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)" -- default
```

That simple command currently installs:

```text
NAMER_INSTALL_MODE=source
NAMER_SOURCE_REPO=Nanja-at-web/namer
NAMER_SOURCE_REF=codex/matching-cleanup-review-db
NAMER_IMAGE=local/namer:codex-matching-cleanup-review-db
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

Install another Namer branch:

```bash
NAMER_SOURCE_REF=your-branch-name \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

Use the official upstream Docker image instead of building from source:

```bash
NAMER_INSTALL_MODE_OVERRIDE=image \
NAMER_IMAGE_OVERRIDE=ghcr.io/theporndatabase/namer:latest \
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
It does not recursively chmod `/namer`, because that path is expected to be a NAS/NFS mount and may contain a large media library.

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
database_path = /config/database
use_database = True
cleanup_enabled = True
review_database_enabled = True
review_database_path = /config/database/review.sqlite
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

## Logs

The host-side installer prints the host log path at startup and again at the end:

```text
Host install log: /tmp/nameratproxmox-YYYYMMDDHHMMSS.log
```

The container-side installer log is available with:

```bash
pct exec <CTID> -- tail -n 120 /var/log/namer-install.log
```

Namer service logs:

```bash
pct exec <CTID> -- journalctl -u namer -n 120 --no-pager
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
| `NAMER_INSTALL_MODE_OVERRIDE` | `source` | `source` builds a Docker image from a Git branch, `image` pulls `NAMER_IMAGE_OVERRIDE` |
| `NAMER_SOURCE_REPO` | `Nanja-at-web/namer` | GitHub repo used in source mode |
| `NAMER_SOURCE_REF` | `codex/matching-cleanup-review-db` | Git branch or tag used in source mode |
| `NAMER_IMAGE_OVERRIDE` | `local/namer:codex-matching-cleanup-review-db` | Docker image name to build or pull |
| `NAMER_CONFIG_URL` | branch default config | URL used to create `/opt/namer/config/namer.cfg` |
| `PUID` | `99` | Namer Docker PUID |
| `PGID` | `100` | Namer Docker PGID |
| `UMASK` | `000` | Namer Docker UMASK |
| `FAILED_DIR_NAME` | `faild` | Failed folder name, matching your current layout |
| `DEST_DIR_NAME` | `dest` | Destination folder name |
| `CORES` | `2` | LXC CPU cores |
| `MEMORY` | `4096` | LXC RAM in MiB |
| `DISK_SIZE` | `24` | LXC root disk size in GiB. Source builds need more root disk than image-only installs |
