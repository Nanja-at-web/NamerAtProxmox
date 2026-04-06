#!/usr/bin/env bash
set -Eeuo pipefail

APP="Namer"
CONFIG_DIR="/opt/namer/config"
STACK_DIR="/opt/namer"
MOUNT_DIR="/mnt/qnap/namer"
SMB_CREDENTIALS="/root/.smbcredentials-namer"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
ENV_FILE="${STACK_DIR}/.env"
CFG_FILE="${CONFIG_DIR}/namer.cfg"
SERVICE_NAME="mnt-qnap-namer.mount"

trap 'echo "[ERROR] Installation failed on line ${LINENO}." >&2' ERR

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Please run this script as root." >&2
    exit 1
  fi
}

msg() {
  echo
  echo "==> $*"
}

ask() {
  local prompt="$1"
  local default="${2-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "$prompt: " value
    printf '%s' "$value"
  fi
}

install_packages() {
  msg "Installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl cifs-utils gnupg
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    msg "Docker already installed"
    return
  fi

  msg "Installing Docker"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

collect_settings() {
  msg "Collecting configuration"
  QNAP_IP="$(ask 'QNAP IP address')"
  QNAP_SHARE="$(ask 'QNAP share name' 'namer')"
  QNAP_USER="$(ask 'QNAP SMB username')"
  QNAP_PASS="$(ask 'QNAP SMB password')"
  TPDB_TOKEN="$(ask 'ThePornDB API token')"
  TZ_VALUE="$(ask 'Timezone' 'Europe/Berlin')"
  PUID_VALUE="$(ask 'Docker PUID' '1000')"
  PGID_VALUE="$(ask 'Docker PGID' '1000')"
  WEB_PORT="$(ask 'Namer web port' '6980')"
}

write_credentials() {
  msg "Writing SMB credentials"
  install -d -m 0755 /root
  cat > "$SMB_CREDENTIALS" <<EOF
username=${QNAP_USER}
password=${QNAP_PASS}
EOF
  chmod 600 "$SMB_CREDENTIALS"
}

mount_share() {
  msg "Creating mount point and mounting QNAP share"
  install -d -m 0775 "$MOUNT_DIR"

  if ! grep -q "${MOUNT_DIR} cifs" /etc/fstab 2>/dev/null; then
    echo "//${QNAP_IP}/${QNAP_SHARE} ${MOUNT_DIR} cifs credentials=${SMB_CREDENTIALS},iocharset=utf8,uid=${PUID_VALUE},gid=${PGID_VALUE},file_mode=0664,dir_mode=0775,nofail,x-systemd.automount,_netdev 0 0" >> /etc/fstab
  fi

  systemctl daemon-reload
  mount -a

  for d in watch work failed DESTINATION; do
    install -d -m 0775 "${MOUNT_DIR}/${d}"
  done
}

write_env() {
  msg "Writing environment file"
  install -d -m 0755 "$STACK_DIR"
  cat > "$ENV_FILE" <<EOF
PUID=${PUID_VALUE}
PGID=${PGID_VALUE}
TZ=${TZ_VALUE}
WEB_PORT=${WEB_PORT}
EOF
}

write_compose() {
  msg "Writing docker compose stack"
  cat > "$COMPOSE_FILE" <<'EOF'
services:
  namer:
    container_name: namer
    image: ghcr.io/theporndatabase/namer:latest
    environment:
      PUID: ${PUID}
      PGID: ${PGID}
      TZ: ${TZ}
      NAMER_CONFIG: /config/namer.cfg
    ports:
      - "${WEB_PORT}:6980"
    volumes:
      - /opt/namer/config:/config
      - /mnt/qnap/namer:/media
    restart: unless-stopped
EOF
}

write_config() {
  msg "Writing namer.cfg"
  install -d -m 0755 "$CONFIG_DIR"
  cat > "$CFG_FILE" <<EOF
[namer]
porndb_token = ${TPDB_TOKEN}
prefer_dir_name_if_available = True
min_file_size = 300
write_namer_log = False
write_namer_failed_log = True
target_extensions = mp4,mkv,avi,mov,flv
update_permissions_ownership = True
set_dir_permissions = 775
set_file_permissions = 664
set_uid = ${PUID_VALUE}
set_gid = ${PGID_VALUE}
inplace_name={full_site} - {date} - {name} [WEBDL-{resolution}].{ext}

[Phash]
search_phash = True
send_phash = False
use_alt_phash_tool = False
use_gpu = False

[metadata]
write_nfo = False
enabled_tagging = False
enabled_poster = False
image_format = png
enable_metadataapi_genres = False
default_genre = Adult
mark_collected = False

[duplicates]
preserve_duplicates = True
max_desired_resolutions = -1
desired_codec = hevc, h264

[watchdog]
ignored_dir_regex = .*_UNPACK_.*
del_other_files = False
extra_sleep_time = 30
queue_limit = 0
queue_sleep_time = 5
new_relative_path_name={full_site}/{full_site} - {date} - {name} [WEBDL-{resolution}].{ext}
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/DESTINATION
web = True
port = 6980
host = 0.0.0.0
web_root =
allow_delete_files = False
add_columns_from_log = False
add_complete_column = False
debug = False
manual_mode = False
diagnose_errors = False

[webhook]
webhook_enabled = False
webhook_url =
EOF
}

start_stack() {
  msg "Starting Namer"
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
}

show_result() {
  local ip
  ip="$(hostname -I | awk '{print $1}')"
  echo
  echo "Installation finished."
  echo "QNAP mount: ${MOUNT_DIR}"
  echo "Namer config: ${CFG_FILE}"
  echo "Web UI: http://${ip}:${WEB_PORT}/"
  echo
  echo "If you want to edit the config later:"
  echo "  nano ${CFG_FILE}"
  echo "  docker compose --env-file ${ENV_FILE} -f ${COMPOSE_FILE} up -d"
}

main() {
  require_root
  collect_settings
  install_packages
  install_docker
  write_credentials
  mount_share
  write_env
  write_compose
  write_config
  start_stack
  show_result
}

main "$@"
