# NamerAtProxmox

Proxmox VE Community-Scripts-style LXC installer for [ThePornDatabase Namer](https://github.com/ThePornDatabase/namer).

## Run the container creator

Run this on a Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/ct/namer.sh)"
```

If you run it from a non-`main` branch, replace `main` in the URL with your branch name.

## Defaults

- App: `Namer`
- OS: Debian 13 LXC
- CPU/RAM/Disk: `2` cores, `2048` MiB RAM, `8` GiB disk
- Web UI: `http://<container-ip>:6980`
- QNAP SMB share: `//192.168.1.24/namer`
- Container mount point: `/namer`
- Namer folders:
  - `/namer/watch`
  - `/namer/work`
  - `/namer/failed`
  - `/namer/dest`
  - `/namer/faild` is created as a compatibility symlink to `/namer/failed`.

## Configure QNAP access

Inside the container, edit:

```bash
nano /etc/namer/qnap.env
systemctl restart namer-mount.service namer.service
```

Set `QNAP_USER` and `QNAP_PASSWORD` if the share does not allow guest access. The default IP is `192.168.1.24`.

## Configure Namer

Inside the container, edit:

```bash
nano /opt/namer/config/namer.cfg
systemctl restart namer.service
```

At minimum, add your TPDB API token and keep these paths:

```ini
watch_dir = /namer/watch
work_dir = /namer/work
failed_dir = /namer/failed
dest_dir = /namer/dest
```
