#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Community installer failed on line ${LINENO}." >&2' ERR

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
WATCH_DIR="${NAMER_WATCH_DIR:-/media/watch}"
WORK_DIR="${NAMER_WORK_DIR:-/media/work}"
FAILED_DIR="${NAMER_FAILED_DIR:-/media/failed}"
DEST_DIR="${NAMER_DEST_DIR:-/media/DESTINATION}"
WEB_ENABLED="${NAMER_WEB_ENABLED:-True}"
WEB_PORT="${NAMER_WEB_PORT:-6980}"
WEB_HOST="${NAMER_WEB_HOST:-0.0.0.0}"
UPDATE_PERMS="${NAMER_UPDATE_PERMISSIONS_OWNERSHIP:-False}"
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

cat > "${NAMER_PATH}/.env" <<EOF
PUID=${PUID_VALUE}
PGID=${PGID_VALUE}
TZ=${TZ_VALUE}
WEB_PORT=${WEB_PORT}
MEDIA_ROOT=${MEDIA_ROOT}
EOF

cat > "${NAMER_PATH}/docker-compose.yml" <<'EOF'
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
EOF

cat > "${NAMER_PATH}/config/namer.cfg" <<EOF
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
EOF

cd "${NAMER_PATH}"
docker compose --env-file "${NAMER_PATH}/.env" -f "${NAMER_PATH}/docker-compose.yml" pull
docker compose --env-file "${NAMER_PATH}/.env" -f "${NAMER_PATH}/docker-compose.yml" up -d

echo "Namer installed successfully. Edit /opt/namer/config/namer.cfg and set a valid ThePornDB token."
