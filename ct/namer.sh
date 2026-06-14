#!/usr/bin/env bash
set -Eeuo pipefail

APP="Namer"
CTID="${CTID:-}"
HOSTNAME="${HOSTNAME:-namer}"
CORES="${CORES:-2}"
MEMORY="${MEMORY:-2048}"
DISK="${DISK:-8}"
BRIDGE="${BRIDGE:-vmbr0}"
NET="${NET:-dhcp}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE="${TEMPLATE:-debian-13-standard_13.1-2_amd64.tar.zst}"
REPO="${REPO:-Nanja-at-web/NamerAtProxmox}"
BRANCH="${BRANCH:-main}"
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/${REPO}/${BRANCH}/install/namer-install.sh}"

msg() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Run this script as root on the Proxmox VE host."
    exit 1
  fi
}

require_pve() {
  if ! command -v pct >/dev/null 2>&1 || ! command -v pveam >/dev/null 2>&1; then
    err "This installer must be run on a Proxmox VE host with pct and pveam available."
    exit 1
  fi
}

next_ctid() {
  if [[ -n "${CTID}" ]]; then
    echo "${CTID}"
  else
    pvesh get /cluster/nextid 2>/dev/null || echo 100
  fi
}

ensure_template() {
  local template_path="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
  if ! pveam list "${TEMPLATE_STORAGE}" 2>/dev/null | awk '{print $1}' | grep -qx "${template_path}"; then
    msg "Downloading ${TEMPLATE} to ${TEMPLATE_STORAGE}"
    pveam update >/dev/null
    pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
  fi
  echo "${template_path}"
}

main() {
  require_root
  require_pve

  CTID="$(next_ctid)"
  if pct status "${CTID}" >/dev/null 2>&1; then
    err "CTID ${CTID} already exists. Set CTID=<free-id> and rerun."
    exit 1
  fi

  local template_path
  template_path="$(ensure_template)"

  msg "Creating ${APP} LXC ${CTID}"
  pct create "${CTID}" "${template_path}" \
    -hostname "${HOSTNAME}" \
    -cores "${CORES}" \
    -memory "${MEMORY}" \
    -rootfs "${STORAGE}:${DISK}" \
    -net0 "name=eth0,bridge=${BRIDGE},ip=${NET}" \
    -features "nesting=1,keyctl=1,mount=cifs" \
    -unprivileged 1 \
    -onboot 1 \
    -tags "media;rename;tpdb"

  msg "Starting LXC ${CTID}"
  pct start "${CTID}"

  msg "Waiting for container network"
  for _ in {1..60}; do
    if pct exec "${CTID}" -- ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  msg "Running Namer installer from ${INSTALL_URL}"
  local installer
  installer="$(curl -fsSL "${INSTALL_URL}")"
  pct exec "${CTID}" -- bash -c "${installer}"

  local ip
  ip="$(pct exec "${CTID}" -- hostname -I 2>/dev/null | awk '{print $1}')"
  ok "${APP} LXC ${CTID} created."
  ok "Web UI: http://${ip}:6980"
  ok "QNAP config: pct exec ${CTID} -- nano /etc/namer/qnap.env"
  ok "Namer config: pct exec ${CTID} -- nano /opt/namer/config/namer.cfg"
}

main "$@"
