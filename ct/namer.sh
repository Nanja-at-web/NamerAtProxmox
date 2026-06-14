#!/usr/bin/env bash
set -Eeuo pipefail

APP="Namer"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main}"
CTID="${CTID:-}"
HOSTNAME="${HOSTNAME:-namer}"
PASSWORD="${PASSWORD:-}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
CONTAINER_STORAGE="${CONTAINER_STORAGE:-local-lvm}"
CORES="${CORES:-2}"
MEMORY="${MEMORY:-2048}"
SWAP="${SWAP:-512}"
DISK_SIZE="${DISK_SIZE:-8}"
BRIDGE="${BRIDGE:-vmbr0}"
IP_CONFIG="${IP_CONFIG:-dhcp}"
HOST_NAMER_PATH="${HOST_NAMER_PATH:-/namer}"
CT_NAMER_PATH="${CT_NAMER_PATH:-/namer}"
QNAP_IP="${QNAP_IP:-192.168.1.24}"
NAMER_PORT="${NAMER_PORT:-6980}"
PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-000}"
FAILED_DIR_NAME="${FAILED_DIR_NAME:-faild}"
DEST_DIR_NAME="${DEST_DIR_NAME:-dest}"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
fail() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

next_ctid() {
  local highest
  highest="$(pct list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n | tail -1)"
  if [[ -z "$highest" ]]; then
    echo 100
  else
    echo $((highest + 1))
  fi
}

latest_debian_template() {
  pveam update >/dev/null
  pveam available --section system | awk '/debian-[0-9]+.*-standard_/ {print $2}' | sort -V | tail -1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root on the Proxmox VE host."
fi

need_cmd pct
need_cmd pveam
need_cmd curl

if [[ ! -d "$HOST_NAMER_PATH" ]]; then
  cat >&2 <<EOF
The host bind-mount source does not exist: $HOST_NAMER_PATH

Mount your QNAP share on the Proxmox host first, for example:
  mkdir -p $HOST_NAMER_PATH
  apt install -y cifs-utils
  mount -t cifs //$QNAP_IP/namer $HOST_NAMER_PATH -o username=YOUR_USER,password=YOUR_PASSWORD,uid=$((100000 + PUID)),gid=$((100000 + PGID)),iocharset=utf8,noperm

Then rerun this script. Override HOST_NAMER_PATH if your share is mounted elsewhere.
EOF
  exit 1
fi

for dir in watch work "$FAILED_DIR_NAME" "$DEST_DIR_NAME"; do
  mkdir -p "$HOST_NAMER_PATH/$dir"
done

if [[ -z "$CTID" ]]; then
  CTID="$(next_ctid)"
fi

if pct status "$CTID" >/dev/null 2>&1; then
  fail "Container ID $CTID already exists. Set CTID=<free-id> and rerun."
fi

TEMPLATE="${TEMPLATE:-$(latest_debian_template)}"
[[ -n "$TEMPLATE" ]] || fail "Could not find a Debian standard LXC template with pveam."

if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -Fxq "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE"; then
  info "Downloading template $TEMPLATE to $TEMPLATE_STORAGE"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

info "Creating $APP LXC $CTID"
pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap "$SWAP" \
  --rootfs "$CONTAINER_STORAGE:$DISK_SIZE" \
  --net0 "name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG" \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --onboot 1 \
  --mp0 "$HOST_NAMER_PATH,mp=$CT_NAMER_PATH" \
  ${PASSWORD:+--password "$PASSWORD"}

info "Starting LXC $CTID"
pct start "$CTID"
sleep 5

info "Installing Docker and Namer inside LXC"
install_script="$(curl -fsSL "$RAW_BASE/install/namer-install.sh")"
pct exec "$CTID" -- env \
  NAMER_PORT="$NAMER_PORT" \
  PUID="$PUID" \
  PGID="$PGID" \
  UMASK="$UMASK" \
  FAILED_DIR_NAME="$FAILED_DIR_NAME" \
  DEST_DIR_NAME="$DEST_DIR_NAME" \
  bash -s <<<"$install_script"

IP_ADDR="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
ok "$APP LXC created successfully."
echo "Container ID: $CTID"
echo "QNAP/host bind mount: $HOST_NAMER_PATH -> $CT_NAMER_PATH"
echo "Namer media mount: $CT_NAMER_PATH -> /media inside Docker"
if [[ -n "$IP_ADDR" ]]; then
  echo "WebUI: http://$IP_ADDR:$NAMER_PORT"
else
  echo "WebUI port: $NAMER_PORT"
fi
