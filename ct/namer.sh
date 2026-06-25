#!/usr/bin/env bash
set -Eeuo pipefail

# Copyright (c) 2026 Nanja-at-web
# Inspired by the Proxmox VE Helper-Scripts community installer flow.

APP="Namer"
NSAPP="namer"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main}"
LOG_FILE="${LOG_FILE:-/tmp/${NSAPP}-create-$(date +%Y%m%d%H%M%S).log}"

YW=$'\033[33m'
BL=$'\033[36m'
GN=$'\033[1;92m'
RD=$'\033[01;31m'
CM=$'\033[0;36m'
BOLD=$'\033[1m'
CL=$'\033[m'
CLEAR_LINE=$'\r\033[2K'
INFO="${BL}[i]${CL}"
OK="${GN}[OK]${CL}"
ERROR="${RD}[ERROR]${CL}"
CREATING="${CM}[+]${CL}"
DEFAULT="${BL}[DEFAULT]${CL}"
ADVANCED="${YW}[ADVANCED]${CL}"

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

header_info() {
  clear 2>/dev/null || true
  cat <<EOF
${BL}
    _   __
   / | / /___ _____ ___  ___  _____
  /  |/ / __ \`/ __ \`__ \\/ _ \\/ ___/
 / /|  / /_/ / / / / / /  __/ /
/_/ |_/\\__,_/_/ /_/ /_/\\___/_/
${CL}
EOF
}

msg_info() { echo -ne " ${INFO} ${YW}$*${CL}"; }
msg_ok() { echo -e "${CLEAR_LINE} ${OK} ${GN}$*${CL}"; }
msg_error() {
  echo -e "${CLEAR_LINE} ${ERROR} ${RD}$*${CL}" >&2
  echo -e " ${INFO} Log: ${BL}${LOG_FILE}${CL}" >&2
  tail -n 80 "$LOG_FILE" >&2 2>/dev/null || true
  exit 1
}

error_handler() {
  local exit_code="$?"
  local line_number="$1"
  echo -e "\n ${ERROR} Script failed at line ${line_number} with exit code ${exit_code}" >&2
  echo -e " ${INFO} Log: ${BL}${LOG_FILE}${CL}" >&2
  tail -n 80 "$LOG_FILE" >&2 2>/dev/null || true
  exit "$exit_code"
}
trap 'error_handler $LINENO' ERR

run_quiet() {
  local label="$1"
  shift
  msg_info "$label"
  if "$@" >>"$LOG_FILE" 2>&1; then
    msg_ok "$label"
  else
    msg_error "$label"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || msg_error "Required command not found: $1"
}

prompt_input() {
  local title="$1"
  local text="$2"
  local value="$3"
  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
    whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" --inputbox "$text" 10 68 "$value" 3>&1 1>&2 2>&3
  else
    printf "%s" "$value"
  fi
}

prompt_yesno() {
  local title="$1"
  local text="$2"
  local default_answer="$3"
  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
    if [[ "$default_answer" == "yes" ]]; then
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" --yesno "$text" 10 68
    else
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "$title" --defaultno --yesno "$text" 10 68
    fi
  else
    [[ "$default_answer" == "yes" ]]
  fi
}

next_ctid() {
  if command -v pvesh >/dev/null 2>&1; then
    pvesh get /cluster/nextid
    return
  fi
  local highest
  highest="$(pct list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n | tail -1)"
  [[ -z "$highest" ]] && echo 100 || echo $((highest + 1))
}

latest_debian_template() {
  pveam update >>"$LOG_FILE" 2>&1
  pveam available --section system | awk '/debian-[0-9]+.*-standard_/ {print $2}' | sort -V | tail -1
}

root_check() {
  [[ "${EUID}" -eq 0 ]] || msg_error "Run this script as root on the Proxmox VE host."
}

pve_check() {
  command -v pveversion >/dev/null 2>&1 || msg_error "This script must run on a Proxmox VE host."
}

mount_check() {
  if [[ ! -d "$HOST_NAMER_PATH" ]]; then
    cat >&2 <<EOF
${ERROR} The host bind-mount source does not exist: ${HOST_NAMER_PATH}

Mount your QNAP NFS export on the Proxmox host first, for example:
  apt install -y nfs-common
  mkdir -p ${HOST_NAMER_PATH}
  showmount -e ${QNAP_IP}
  mount -t nfs ${QNAP_IP}:${QNAP_EXPORT} ${HOST_NAMER_PATH}

Then rerun this script. Override HOST_NAMER_PATH or QNAP_EXPORT if your share is mounted elsewhere.
EOF
    exit 1
  fi
}

default_settings() {
  METHOD="default"
  VERBOSE="no"
  [[ -z "$CTID" ]] && CTID="$(next_ctid)"
}

advanced_settings() {
  METHOD="advanced"
  VERBOSE="no"
  [[ -z "$CTID" ]] && CTID="$(next_ctid)"

  CTID="$(prompt_input "Container ID" "Set the Container ID." "$CTID")"
  CT_HOSTNAME="$(prompt_input "Hostname" "Set the container hostname." "$CT_HOSTNAME")"
  DISK_SIZE="$(prompt_input "Disk Size" "Set root disk size in GB." "$DISK_SIZE")"
  CORES="$(prompt_input "CPU Cores" "Set CPU core count." "$CORES")"
  MEMORY="$(prompt_input "Memory" "Set RAM in MiB." "$MEMORY")"
  SWAP="$(prompt_input "Swap" "Set swap in MiB." "$SWAP")"
  BRIDGE="$(prompt_input "Network Bridge" "Set Proxmox bridge." "$BRIDGE")"
  IP_CONFIG="$(prompt_input "IPv4 Address" "Use dhcp or a static address like 192.168.1.50/24,gw=192.168.1.1." "$IP_CONFIG")"
  CONTAINER_STORAGE="$(prompt_input "Container Storage" "Set container storage." "$CONTAINER_STORAGE")"
  TEMPLATE_STORAGE="$(prompt_input "Template Storage" "Set template storage." "$TEMPLATE_STORAGE")"
  HOST_NAMER_PATH="$(prompt_input "Namer Media Path" "Set host path for the QNAP/NFS media mount." "$HOST_NAMER_PATH")"
  NAMER_PORT="$(prompt_input "WebUI Port" "Set the Namer WebUI port." "$NAMER_PORT")"

  if prompt_yesno "Container Type" "Use an unprivileged container?\n\nFor QNAP/NFS permission edge cases, privileged can be easier." "$([[ "$CT_UNPRIVILEGED" == "1" ]] && echo yes || echo no)"; then
    CT_UNPRIVILEGED="1"
  else
    CT_UNPRIVILEGED="0"
  fi
}

choose_install_mode() {
  local choice="${1:-}"
  if [[ -z "$choice" ]] && command -v whiptail >/dev/null 2>&1 && [[ -t 0 ]]; then
    choice="$(whiptail \
      --backtitle "Proxmox VE Helper Scripts" \
      --title "Community-Scripts Options" \
      --ok-button "Select" --cancel-button "Exit Script" \
      --notags \
      --menu "\nChoose an option:\n Use TAB or Arrow keys to navigate, ENTER to select.\n" \
      16 60 4 \
      "1" "Default Install" \
      "2" "Advanced Install" \
      "3" "Exit" \
      --default-item "1" \
      3>&1 1>&2 2>&3)" || exit 0
  fi

  case "${choice:-default}" in
    1 | default | DEFAULT)
      header_info
      echo -e "${DEFAULT} ${BOLD}${BL}Using Default Settings on node $(hostname)${CL}"
      default_settings
      ;;
    2 | advanced | ADVANCED)
      header_info
      echo -e "${ADVANCED} ${BOLD}${RD}Using Advanced Install on node $(hostname)${CL}"
      advanced_settings
      ;;
    3 | exit | EXIT)
      exit 0
      ;;
    *)
      msg_error "Unknown install option: $choice"
      ;;
  esac
}

echo_settings() {
  echo -e "${INFO} Using ${BL}${CTID}${CL} as Container ID"
  echo -e "${INFO} Using ${BL}${CT_HOSTNAME}${CL} as Hostname"
  echo -e "${INFO} Using ${BL}${DISK_SIZE}GB${CL} Disk, ${BL}${CORES}${CL} CPU, ${BL}${MEMORY}MiB${CL} RAM"
  echo -e "${INFO} Using ${BL}${CONTAINER_STORAGE}${CL} for container storage"
  echo -e "${INFO} Using ${BL}${BRIDGE}${CL} with ${BL}${IP_CONFIG}${CL}"
  echo -e "${INFO} Using ${BL}$([[ "$CT_UNPRIVILEGED" == "1" ]] && echo "Unprivileged" || echo "Privileged")${CL} container"
  echo -e "${INFO} Using ${BL}${HOST_NAMER_PATH}${CL} as QNAP/NFS media mount"
  echo -e "${INFO} Installing ${BL}${NAMER_SOURCE_REPO}@${NAMER_SOURCE_REF}${CL}"
  echo -e "${INFO} Logging to ${BL}${LOG_FILE}${CL}"
  echo
}

build_container() {
  if [[ ! "$CT_UNPRIVILEGED" =~ ^[01]$ ]]; then
    msg_error "CT_UNPRIVILEGED must be 0 or 1."
  fi

  mount_check

  for dir in watch work "$FAILED_DIR_NAME" "$DEST_DIR_NAME"; do
    mkdir -p "$HOST_NAMER_PATH/$dir"
  done

  if pct status "$CTID" >/dev/null 2>&1; then
    msg_error "Container ID $CTID already exists. Set CTID=<free-id> and rerun."
  fi

  TEMPLATE="${TEMPLATE:-$(latest_debian_template)}"
  [[ -n "$TEMPLATE" ]] || msg_error "Could not find a Debian standard LXC template with pveam."

  if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -Fxq "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE"; then
    run_quiet "Downloading Debian template" pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
  fi

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

  [[ -n "$PASSWORD" ]] && create_args+=(--password "$PASSWORD")

  run_quiet "Creating LXC container" pct create "${create_args[@]}"
  run_quiet "Starting LXC Container" pct start "$CTID"

  msg_info "Waiting for network in LXC container"
  local ip_in_lxc=""
  for _ in {1..60}; do
    ip_in_lxc="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || true)"
    [[ -n "$ip_in_lxc" ]] && break
    sleep 1
  done
  [[ -n "$ip_in_lxc" ]] || msg_error "No network in LXC container after 60 seconds"
  msg_ok "Network Connected: ${BL}${ip_in_lxc}${CL}"

  msg_info "Installing ${APP}"
  echo
  install_script="$(curl -fsSL "$RAW_BASE/install/namer-install.sh")"
  set +e
  pct exec "$CTID" -- env \
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
    bash -s <<<"$install_script" 2>&1 | tee -a "$LOG_FILE"
  install_status=${PIPESTATUS[0]}
  set -e
  if [[ "$install_status" -eq 0 ]]; then
    msg_ok "Installed ${APP}"
  else
    msg_error "Installing ${APP}"
  fi

  IP_ADDR="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
}

description() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING} ${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO} ${YW}Access it using the following URL:${CL}"
  if [[ -n "${IP_ADDR:-}" ]]; then
    echo -e "${INFO} ${BL}http://${IP_ADDR}:${NAMER_PORT}${CL}"
  else
    echo -e "${INFO} ${BL}Port ${NAMER_PORT}${CL}"
  fi
  echo -e "${INFO} ${YW}Host install log:${CL} ${BL}${LOG_FILE}${CL}"
  echo -e "${INFO} ${YW}Container install log:${CL} ${BL}pct exec ${CTID} -- tail -n 120 /var/log/namer-install.log${CL}"
  echo -e "${INFO} ${YW}Namer service logs:${CL} ${BL}pct exec ${CTID} -- journalctl -u namer -n 120 --no-pager${CL}"
}

main() {
  cat >"$LOG_FILE" <<EOF
NamerAtProxmox installation log
Started: $(date -Is)
Command user: $(whoami)
EOF

  root_check
  pve_check
  need_cmd pct
  need_cmd pveam
  need_cmd curl

  choose_install_mode "${1:-}"
  echo_settings
  build_container
  description
}

main "$@"
