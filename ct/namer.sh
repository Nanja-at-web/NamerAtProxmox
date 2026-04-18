#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 community-scripts ORG
# Author: Nanja-at-web
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/ThePornDatabase/namer

APP="Namer"
var_tags="${var_tags:-media;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
base_settings
variables
color
catch_errors

ensure_namer_app_defaults_file() {
  local defaults_dir="/usr/local/community-scripts/defaults"
  local defaults_file="${defaults_dir}/namer.vars"

  mkdir -p "$defaults_dir"
  if [[ ! -f "$defaults_file" ]]; then
    cat > "$defaults_file" <<'EOF'
# App-specific defaults for Namer
var_cpu=2
var_ram=2048
var_disk=8
var_os=debian
var_version=13
var_unprivileged=1
var_tags=media;docker
var_nesting=1
var_keyctl=1
var_mknod=0
var_fuse=no
var_tun=no
var_gpu=no
var_verbose=no
var_protection=no
var_timezone=
var_apt_cacher=no
var_container_storage=
var_template_storage=
EOF
    chmod 0644 "$defaults_file"
  fi
}

ask_mount_settings() {
  echo
  echo "NFS mount configuration for Namer"
  echo

  read -r -p "NAS host/IP: " NAS_HOST
  [[ -n "${NAS_HOST:-}" ]] || { msg_error "NAS host/IP must not be empty"; exit 1; }

  read -r -p "NAS export path (example: /namer): " NAS_EXPORT
  [[ -n "${NAS_EXPORT:-}" ]] || { msg_error "NAS export path must not be empty"; exit 1; }

  read -r -p "Host mount path [/mnt/bindmounts/qnap-namer]: " HOST_MOUNT
  HOST_MOUNT="${HOST_MOUNT:-/mnt/bindmounts/qnap-namer}"
  [[ "$HOST_MOUNT" = /* ]] || { msg_error "Host mount path must be an absolute path"; exit 1; }

  read -r -p "Container mount path [/mnt/namer-share]: " CT_MOUNT
  CT_MOUNT="${CT_MOUNT:-/mnt/namer-share}"
  [[ "$CT_MOUNT" = /* ]] || { msg_error "Container mount path must be an absolute path"; exit 1; }

  read -r -p "Create watch/work/failed/dest automatically? [true]: " AUTO_CREATE_DIRS
  AUTO_CREATE_DIRS="${AUTO_CREATE_DIRS:-true}"

  read -r -p "Write persistent /etc/fstab entry on Proxmox host? [false]: " WRITE_FSTAB
  WRITE_FSTAB="${WRITE_FSTAB:-false}"

  read -r -p "Run optional write test after bind mount? [false]: " RUN_WRITE_TEST
  RUN_WRITE_TEST="${RUN_WRITE_TEST:-false}"

  read -r -p "Additional NFS mount options [empty]: " NFS_OPTIONS
  NFS_OPTIONS="${NFS_OPTIONS:-}"
}

ask_tpdb_token() {
  echo
  echo "Namer requires a valid ThePornDB API token to start."
  echo "Please paste the token now."
  echo "The input is hidden, so no characters will be shown while typing."
  echo
  read -r -s -p "ThePornDB API token: " TPDB_TOKEN
  echo

  if [[ -z "${TPDB_TOKEN:-}" ]]; then
    msg_error "ThePornDB API token must not be empty"
    exit 1
  fi

  msg_ok "Token received"
}

ensure_nfs_client_tools() {
  if command -v mount.nfs >/dev/null 2>&1; then
    return
  fi

  msg_info "Installing NFS client tools on Proxmox host"
  apt-get update
  apt-get install -y nfs-common
  msg_ok "NFS client tools installed"
}

run_host_mount_setup() {
  local source_path="${NAS_HOST}:${NAS_EXPORT}"
  local mount_opts="${NFS_OPTIONS:-}"

  msg_info "Preparing host mount path"
  mkdir -p "$HOST_MOUNT"

  ensure_nfs_client_tools

  if mountpoint -q "$HOST_MOUNT"; then
    msg_info "Host mount already active at $HOST_MOUNT"
  else
    msg_info "Mounting ${source_path} to ${HOST_MOUNT}"
    if [[ -n "$mount_opts" ]]; then
      mount -t nfs -o "$mount_opts" "$source_path" "$HOST_MOUNT"
    else
      mount -t nfs "$source_path" "$HOST_MOUNT"
    fi
  fi

  if ! mountpoint -q "$HOST_MOUNT"; then
    msg_error "Mount failed: $HOST_MOUNT is not an active mount point"
    exit 1
  fi

  if [[ "$AUTO_CREATE_DIRS" == "true" ]]; then
    msg_info "Ensuring required Namer directories exist on mounted share"
    msg_info "Existing NAS directories are reused. Nothing is deleted."
    mkdir -p \
      "$HOST_MOUNT/watch" \
      "$HOST_MOUNT/work" \
      "$HOST_MOUNT/failed" \
      "$HOST_MOUNT/dest"
  fi

  if [[ "$WRITE_FSTAB" == "true" ]]; then
    local fstab_opts="${NFS_OPTIONS:-defaults}"
    local fstab_line="${source_path} ${HOST_MOUNT} nfs ${fstab_opts} 0 0"

    if ! grep -Fqs "$HOST_MOUNT " /etc/fstab; then
      echo "$fstab_line" >> /etc/fstab
      msg_ok "/etc/fstab entry added"
    else
      msg_info "/etc/fstab already contains an entry for $HOST_MOUNT"
    fi
  fi

  msg_ok "Host mount prepared"
}

attach_mount_to_ct() {
  msg_info "Attaching bind mount to CT ${CTID}"

  if pct config "$CTID" | grep -qE "^mp0:"; then
    msg_info "CT ${CTID} already has mp0 configured, replacing it"
    pct set "$CTID" -delete mp0
  fi

  pct set "$CTID" -mp0 "${HOST_MOUNT},mp=${CT_MOUNT}"
  pct reboot "$CTID"

  msg_info "Waiting for CT ${CTID} to come back"
  sleep 8
  msg_ok "Bind mount attached"
}

run_host_mount_check() {
  msg_info "Checking host mount"
  mountpoint -q "$HOST_MOUNT" || { msg_error "Host mount is not active: $HOST_MOUNT"; exit 1; }

  for d in watch work failed dest; do
    [[ -d "$HOST_MOUNT/$d" ]] || { msg_error "Missing directory on host mount: $HOST_MOUNT/$d"; exit 1; }
  done

  msg_info "Checking mount visibility inside CT ${CTID}"
  pct exec "$CTID" -- test -d "$CT_MOUNT" || {
    msg_error "Container does not see mount path: $CT_MOUNT"
    exit 1
  }

  for d in watch work failed dest; do
    pct exec "$CTID" -- test -d "$CT_MOUNT/$d" || {
      msg_error "Missing directory inside CT: $CT_MOUNT/$d"
      exit 1
    }
  done

  if [[ "$RUN_WRITE_TEST" == "true" ]]; then
    msg_info "Running write test with a temporary file only"
    local test_file_host="$HOST_MOUNT/watch/.namer_mount_test_$$"
    local test_file_ct="$CT_MOUNT/watch/.namer_mount_test_$$"

    echo "namer mount test" > "$test_file_host"
    pct exec "$CTID" -- test -f "$test_file_ct" || {
      rm -f "$test_file_host"
      msg_error "Write test failed: file not visible inside CT"
      exit 1
    }

    pct exec "$CTID" -- rm -f "$test_file_ct"
    [[ ! -f "$test_file_host" ]] || {
      rm -f "$test_file_host"
      msg_error "Write test failed: file deletion did not reflect on host"
      exit 1
    }
  fi

  msg_ok "Mount check passed"
}

write_ct_installer() {
  msg_info "Writing embedded Namer installer into CT ${CTID}"

  pct exec "$CTID" -- bash -lc 'cat >/root/namer-install-community.sh <<'\''EOF'\''
#!/usr/bin/env bash
# Copyright (c) 2026 Nanja-at-web
# Author: Nanja-at-web
# License: MIT
# Source: https://github.com/ThePornDatabase/namer
set -Eeuo pipefail

trap '\''echo "[ERROR] Community installer failed on line ${LINENO}." >&2'\'' ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Please run this script as root inside the container." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
MEDIA_ROOT="${NAMER_MEDIA_ROOT:-/mnt/namer-share}"
TPDB_TOKEN="${NAMER_TPDB_TOKEN:-}"
TZ_VALUE="${TZ:-Europe/Berlin}"
PUID_VALUE="${PUID:-1000}"
PGID_VALUE="${PGID:-1000}"
WATCH_DIR="${NAMER_WATCH_DIR:-/media/watch}"
WORK_DIR="${NAMER_WORK_DIR:-/media/work}"
FAILED_DIR="${NAMER_FAILED_DIR:-/media/failed}"
DEST_DIR="${NAMER_DEST_DIR:-/media/dest}"
WEB_ENABLED="${NAMER_WEB_ENABLED:-True}"
WEB_PORT="${NAMER_WEB_PORT:-6980}"
WEB_HOST="${NAMER_WEB_HOST:-0.0.0.0}"
UPDATE_PERMS="${NAMER_UPDATE_PERMISSIONS_OWNERSHIP:-False}"
NAMER_PATH="/opt/namer"

if [[ -z "$TPDB_TOKEN" ]]; then
  echo
  echo "Namer requires a valid ThePornDB API token to start."
  echo "Please paste the token now."
  echo "The input is hidden, so no characters will be shown while typing."
  echo
  read -r -s -p "ThePornDB API token: " TPDB_TOKEN
  echo
fi

if [[ -z "$TPDB_TOKEN" ]]; then
  echo "ERROR: ThePornDB API token must not be empty." >&2
  exit 1
fi

echo "Token received. Continuing with Namer configuration."

apt-get update
apt-get install -y curl ca-certificates

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker >/dev/null 2>&1 || true

mkdir -p "${MEDIA_ROOT}/watch" \
         "${MEDIA_ROOT}/work" \
         "${MEDIA_ROOT}/failed" \
         "${MEDIA_ROOT}/dest" \
         "${NAMER_PATH}/config"

echo "${MEDIA_ROOT}" >/root/.namer-media-root

cat > "${NAMER_PATH}/.env" <<EOF2
PUID=${PUID_VALUE}
PGID=${PGID_VALUE}
TZ=${TZ_VALUE}
WEB_PORT=${WEB_PORT}
MEDIA_ROOT=${MEDIA_ROOT}
EOF2

cat > "${NAMER_PATH}/docker-compose.yml" <<'\''EOF2'\''
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
      - ${MEDIA_ROOT}:/media
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:${WEB_PORT}/ >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 20s
EOF2

cat > "${NAMER_PATH}/config/namer.cfg" <<EOF2
[namer]
porndb_token = ${TPDB_TOKEN}
prefer_dir_name_if_available = True
min_file_size = 300
write_namer_log = False
write_namer_failed_log = True
target_extensions = mp4,mkv,avi,mov,flv
update_permissions_ownership = ${UPDATE_PERMS}
set_dir_permissions = 775
set_file_permissions = 664
set_uid =
set_gid =
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
watch_dir = ${WATCH_DIR}
work_dir = ${WORK_DIR}
failed_dir = ${FAILED_DIR}
dest_dir = ${DEST_DIR}
web = ${WEB_ENABLED}
port = ${WEB_PORT}
host = ${WEB_HOST}
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
EOF2

cd "${NAMER_PATH}"
docker compose --env-file "${NAMER_PATH}/.env" -f "${NAMER_PATH}/docker-compose.yml" pull
docker compose --env-file "${NAMER_PATH}/.env" -f "${NAMER_PATH}/docker-compose.yml" up -d

sleep 8
if ! docker ps --format "{{.Names}}" | grep -qx "namer"; then
  echo "ERROR: Namer did not stay running. Check: docker logs namer" >&2
  docker logs --tail 100 namer || true
  exit 1
fi

for _ in $(seq 1 12); do
  HEALTH_STATUS="$(docker inspect --format '\''{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}'\'' namer 2>/dev/null || true)"
  if [[ "$HEALTH_STATUS" == "healthy" ]]; then
    break
  fi
  sleep 5
done

if [[ "${HEALTH_STATUS:-}" != "healthy" ]]; then
  echo "ERROR: Namer container did not become healthy. Check: docker logs namer" >&2
  docker logs --tail 100 namer || true
  exit 1
fi

IP_ADDR=$(hostname -I | awk "{print \$1}")
echo "Namer installed successfully. Web UI: http://${IP_ADDR}:${WEB_PORT}"
EOF
chmod +x /root/namer-install-community.sh'
  msg_ok "Embedded installer written to CT"
}

run_namer_installer() {
  write_ct_installer
  msg_info "Running embedded Namer installer inside CT $CTID"
  if pct exec "$CTID" -- env NAMER_MEDIA_ROOT="$CT_MOUNT" NAMER_WEB_PORT=6980 NAMER_TPDB_TOKEN="$TPDB_TOKEN" bash -lc 'bash /root/namer-install-community.sh'
  then
    msg_ok "Namer installed successfully in CT $CTID"
    unset TPDB_TOKEN
  else
    unset TPDB_TOKEN
    msg_error "Namer installer failed in CT $CTID"
    exit 1
  fi
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating Namer container"
  if pct exec "$CTID" -- bash -lc 'test -f /opt/namer/docker-compose.yml'; then
    pct exec "$CTID" -- bash -lc 'cd /opt/namer && docker compose --env-file /opt/namer/.env -f /opt/namer/docker-compose.yml pull && docker compose --env-file /opt/namer/.env -f /opt/namer/docker-compose.yml up -d'
    msg_ok "Updated Namer"
  else
    msg_error "No existing Namer installation found in CT $CTID"
    exit 1
  fi
  exit
}

main() {
  ensure_namer_app_defaults_file
  ask_mount_settings
  ask_tpdb_token
  run_host_mount_setup

  start
  build_container

  attach_mount_to_ct
  run_host_mount_check
  run_namer_installer

  description
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6980${CL}"
  echo -e "${INFO}${YW} NFS source:${CL}"
  echo -e "${TAB}${BGN}${NAS_HOST}:${NAS_EXPORT}${CL}"
  echo -e "${INFO}${YW} Host mount path:${CL}"
  echo -e "${TAB}${BGN}${HOST_MOUNT}${CL}"
  echo -e "${INFO}${YW} Container mount path:${CL}"
  echo -e "${TAB}${BGN}${CT_MOUNT}${CL}"
  echo -e "${INFO}${YW} Required directories on the NAS share:${CL}"
  echo -e "${TAB}${BGN}watch${CL}"
  echo -e "${TAB}${BGN}work${CL}"
  echo -e "${TAB}${BGN}failed${CL}"
  echo -e "${TAB}${BGN}dest${CL}"
  echo -e "${INFO}${YW} Namer config file:${CL}"
  echo -e "${TAB}${BGN}/opt/namer/config/namer.cfg${CL}"
}

main "$@"
