#!/usr/bin/env bash
set -Eeuo pipefail

APP="Namer"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main}"
LOG_FILE="${LOG_FILE:-/tmp/nameratproxmox-$(date +%Y%m%d%H%M%S).log}"
CTID="${CTID:-}"
CT_HOSTNAME="${CT_HOSTNAME:-${NAMER_HOSTNAME:-namer}}"
CT_UNPRIVILEGED="${CT_UNPRIVILEGED:-1}"
PASSWORD="${PASSWORD:-}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
CONTAINER_STORAGE="${CONTAINER_STORAGE:-local-lvm}"
CORES="${CORES:-2}"
MEMORY="${MEMORY:-4096}"
SWAP="${SWAP:-512}"
DISK_SIZE="${DISK_SIZE:-24}"
BRIDGE="${BRIDGE:-vmbr0}"
IP_CONFIG="${IP_CONFIG:-dhcp}"
HOST_NAMER_PATH="${HOST_NAMER_PATH:-/namer}"
CT_NAMER_PATH="${CT_NAMER_PATH:-/namer}"
QNAP_IP="${QNAP_IP:-192.168.1.24}"
QNAP_EXPORT="${QNAP_EXPORT:-/namer}"
NAMER_PORT="${NAMER_PORT:-6980}"
NAMER_SOURCE_REPO="${NAMER_SOURCE_REPO:-Nanja-at-web/namer}"
NAMER_SOURCE_REF="${NAMER_SOURCE_REF:-codex/matching-cleanup-review-db}"
NAMER_INSTALL_MODE="${NAMER_INSTALL_MODE_OVERRIDE:-source}"
NAMER_IMAGE="${NAMER_IMAGE_OVERRIDE:-local/namer:${NAMER_SOURCE_REF//\//-}}"
NAMER_CONFIG_URL="${NAMER_CONFIG_URL:-https://raw.githubusercontent.com/${NAMER_SOURCE_REPO}/${NAMER_SOURCE_REF}/namer/namer.cfg.default}"
PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-000}"
FAILED_DIR_NAME="${FAILED_DIR_NAME:-faild}"
DEST_DIR_NAME="${DEST_DIR_NAME:-dest}"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $*"; }
fail() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

msg_info() { echo -ne "\033[1;34m[INFO]\033[0m $*..."; }
msg_ok() { echo -e " \033[1;32mOK\033[0m"; }
msg_fail() {
  echo -e " \033[1;31mFAILED\033[0m"
  echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
  echo "Log: $LOG_FILE" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  exit 1
}

run_quiet() {
  local label="$1"
  shift
  msg_info "$label"
  if "$@" >>"$LOG_FILE" 2>&1; then
    msg_ok
  else
    msg_fail "$label"
  fi
}

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
  pveam update >>"$LOG_FILE" 2>&1
  pveam available --section system | awk '/debian-[0-9]+.*-standard_/ {print $2}' | sort -V | tail -1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run this script as root on the Proxmox VE host."
fi

need_cmd pct
need_cmd pveam
need_cmd curl

cat >"$LOG_FILE" <<EOF
NamerAtProxmox installation log
Started: $(date -Is)
Command user: $(whoami)
EOF

if [[ ! "$CT_UNPRIVILEGED" =~ ^[01]$ ]]; then
  fail "CT_UNPRIVILEGED must be 0 or 1."
fi

if [[ ! -d "$HOST_NAMER_PATH" ]]; then
  cat >&2 <<EOF
The host bind-mount source does not exist: $HOST_NAMER_PATH

Mount your QNAP NFS export on the Proxmox host first, for example:
  apt install -y nfs-common
  mkdir -p $HOST_NAMER_PATH
  showmount -e $QNAP_IP
  mount -t nfs $QNAP_IP:$QNAP_EXPORT $HOST_NAMER_PATH

Then rerun this script. Override HOST_NAMER_PATH or QNAP_EXPORT if your share is mounted elsewhere.
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
  run_quiet "Downloading Debian template $TEMPLATE" pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi

echo
echo "NamerAtProxmox"
echo "  CTID:       $CTID"
echo "  Hostname:   $CT_HOSTNAME"
echo "  Privileged: $([[ "$CT_UNPRIVILEGED" == "0" ]] && echo "yes" || echo "no")"
echo "  Disk/RAM:   ${DISK_SIZE}G / ${MEMORY}MiB"
echo "  Source:     ${NAMER_SOURCE_REPO}@${NAMER_SOURCE_REF}"
echo "  Log:        $LOG_FILE"
echo

create_args=(
  "$CTID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE"
  --hostname "$CT_HOSTNAME"
  --cores "$CORES"
  --memory "$MEMORY"
  --swap "$SWAP"
  --rootfs "$CONTAINER_STORAGE:$DISK_SIZE"
  --net0 "name=eth0,bridge=$BRIDGE,ip=$IP_CONFIG"
  --features nesting=1,keyctl=1
  --unprivileged "$CT_UNPRIVILEGED"
  --onboot 1
  --mp0 "$HOST_NAMER_PATH,mp=$CT_NAMER_PATH"
)

if [[ -n "$PASSWORD" ]]; then
  create_args+=(--password "$PASSWORD")
fi

run_quiet "Creating $APP LXC $CTID" pct create "${create_args[@]}"

run_quiet "Starting LXC $CTID" pct start "$CTID"
sleep 5

msg_info "Installing Docker and Namer inside LXC"
install_script="$(curl -fsSL "$RAW_BASE/install/namer-install.sh")"
if pct exec "$CTID" -- env \
  LOG_FILE="/var/log/namer-install.log" \
  NAMER_PORT="$NAMER_PORT" \
  NAMER_INSTALL_MODE="$NAMER_INSTALL_MODE" \
  NAMER_SOURCE_REPO="$NAMER_SOURCE_REPO" \
  NAMER_SOURCE_REF="$NAMER_SOURCE_REF" \
  NAMER_IMAGE="$NAMER_IMAGE" \
  NAMER_CONFIG_URL="$NAMER_CONFIG_URL" \
  PUID="$PUID" \
  PGID="$PGID" \
  UMASK="$UMASK" \
  FAILED_DIR_NAME="$FAILED_DIR_NAME" \
  DEST_DIR_NAME="$DEST_DIR_NAME" \
  bash -s <<<"$install_script" >>"$LOG_FILE" 2>&1; then
  msg_ok
else
  msg_fail "Installing Docker and Namer inside LXC"
fi

IP_ADDR="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
ok "$APP LXC created successfully."
echo "Container ID: $CTID"
echo "Unprivileged: $CT_UNPRIVILEGED"
echo "QNAP/host bind mount: $HOST_NAMER_PATH -> $CT_NAMER_PATH"
echo "Namer install mode: $NAMER_INSTALL_MODE"
echo "Namer source: $NAMER_SOURCE_REPO@$NAMER_SOURCE_REF"
echo "Namer image: $NAMER_IMAGE"
echo "Namer media mount: $CT_NAMER_PATH -> $CT_NAMER_PATH inside Docker"
echo "Host install log: $LOG_FILE"
echo "Container install log: pct exec $CTID -- tail -n 120 /var/log/namer-install.log"
if [[ -n "$IP_ADDR" ]]; then
  echo "WebUI: http://$IP_ADDR:$NAMER_PORT"
else
  echo "WebUI port: $NAMER_PORT"
fi
