#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Host-side installer failed on line ${LINENO}." >&2' ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root on the Proxmox host." >&2
  exit 1
fi

CTID="${CTID:-$(pvesh get /cluster/nextid)}"
HOSTNAME="${HOSTNAME:-namer}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
BRIDGE="${BRIDGE:-vmbr0}"
CORES="${CORES:-2}"
MEMORY="${MEMORY:-2048}"
DISK="${DISK:-8}"
OSTYPE="debian"
OSVERSION="13"
UNPRIVILEGED="1"

if ! command -v pveam >/dev/null 2>&1; then
  echo "This script must be run on a Proxmox VE host." >&2
  exit 1
fi

pveam update
TEMPLATE=$(pveam available --section system | awk '/debian-13-standard/ {print $2; exit}')
if [[ -z "${TEMPLATE:-}" ]]; then
  echo "Unable to find a Debian 13 LXC template." >&2
  exit 1
fi

if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $2}' | grep -qx "$TEMPLATE"; then
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --ostype "$OSTYPE" \
  --arch amd64 \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap 512 \
  --rootfs "$STORAGE:$DISK" \
  --net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
  --unprivileged "$UNPRIVILEGED" \
  --features nesting=1,keyctl=1

pct start "$CTID"
sleep 5
pct exec "$CTID" -- bash -lc 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-standalone.sh)"'

echo "Namer container $CTID created successfully."
echo "Bind-mount your NAS share into /mnt/namer-share inside the CT for production use."
