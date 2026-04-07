#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 community-scripts ORG
# Author: OpenAI
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

run_internal_namer_installer() {
  local target_ctid="$1"

  pct exec "$target_ctid" -- bash -lc 'cat >/root/namer-install-community.sh <<'\''EOF'\''
#!/usr/bin/env bash
set -Eeuo pipefail

trap '\''echo "[ERROR] Community installer failed on line ${LINENO}." >&2'\'' ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Please run this script as root inside the container." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
MEDIA_ROOT="${NAMER_MEDIA_ROOT:-/mnt/namer-share}"
TPDB_TOKEN="${NAMER_TPDB_TOKEN:-REPLACE_WITH_TPDB_TOKEN}"
TZ_VALUE="${TZ:-Europe/Berlin}"
PUID_VALUE="${PUID:-1000}"
PGID_VALUE="${PGID:-1000}"
WEB_PORT="${NAMER_WEB_PORT:-6980}"
NAMER_PATH="/opt/namer"

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
         "${MEDIA_ROOT}/DESTINATION" \
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
EOF2

cat > "${NAMER_PATH}/config/namer.cfg" <<EOF2
[namer]
porndb_token = ${TPDB_TOKEN}
prefer_dir_name_if_available = True
min_file_size = 300
write_namer_log = False
write_namer_failed_log = True
target_extensions = mp4,mkv,avi,mov,flv
update_permissions_ownership = False
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
EOF2

cd "${NAMER_PATH}"
docker compose --env-file "${NAMER_PATH}/.env" -f "${NAMER_PATH}/docker-compose.yml" pull
docker compose --env-file "${NAMER_PATH}/.env" -f "${NAMER_PATH}/docker-compose.yml" up -d

IP_ADDR=$(hostname -I | awk "{print \$1}")
echo "Namer installed successfully. Web UI: http://${IP_ADDR}:${WEB_PORT}"
echo "If needed, edit /opt/namer/config/namer.cfg and set a valid ThePornDB token."
EOF
chmod +x /root/namer-install-community.sh
NAMER_MEDIA_ROOT=/mnt/namer-share NAMER_WEB_PORT=6980 bash /root/namer-install-community.sh'
}

lxc-attach() {
  if [[ "$#" -ge 6 ]] && [[ "$1" == "-n" ]] && [[ "$3" == "--" ]] && [[ "$4" == "bash" ]] && [[ "$5" == "-c" ]]; then
    local cmd_string="${6:-}"
    if [[ "$cmd_string" == *"raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"* ]]; then
      run_internal_namer_installer "$2"
      return $?
    fi
  fi
  command lxc-attach "$@"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating Namer container"
  if pct exec "$CTID" -- bash -lc 'test -f /opt/namer/docker-compose.yml'; then
    pct exec "$CTID" -- bash -lc 'cd /opt/namer && docker compose pull && docker compose up -d'
    msg_ok "Updated Namer"
  else
    msg_error "No existing Namer installation found in CT $CTID"
    exit 1
  fi
  exit
}

ensure_namer_app_defaults_file
start
build_container

description
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6980${CL}"
echo -e "${INFO}${YW} Recommended media mount inside the container:${CL}"
echo -e "${TAB}${BGN}/mnt/namer-share${CL}"
echo -e "${INFO}${YW} Recommended Namer folders on the mounted share:${CL}"
echo -e "${TAB}${BGN}watch${CL}"
echo -e "${TAB}${BGN}work${CL}"
echo -e "${TAB}${BGN}failed${CL}"
echo -e "${TAB}${BGN}DESTINATION${CL}"
