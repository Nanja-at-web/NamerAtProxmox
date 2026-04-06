#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Installation failed on line ${LINENO}." >&2' ERR

if [[ ${EUID} -ne 0 ]]; then
  echo "Please run this script as root inside the container." >&2
  exit 1
fi

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

require_dir() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "Directory not found: $path" >&2
    exit 1
  fi
}

msg() {
  echo
  echo "==> $*"
}

MEDIA_ROOT="$(ask 'Bound media root inside the LXC' '/mnt/namer-share')"
TPDB_TOKEN="$(ask 'ThePornDB API token')"
TZ_VALUE="$(ask 'Timezone' 'Europe/Berlin')"
PUID_VALUE="$(ask 'Docker PUID' '1000')"
PGID_VALUE="$(ask 'Docker PGID' '1000')"
WEB_PORT="$(ask 'Namer web port' '6980')"

require_dir "$MEDIA_ROOT"

for d in watch work failed DESTINATION; do
  mkdir -p "$MEDIA_ROOT/$d"
done

msg "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates

msg "Installing Docker"
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

msg "Preparing Namer directories"
mkdir -p /opt/namer/config

cat > /opt/namer/.env <<EOF
PUID=${PUID_VALUE}
PGID=${PGID_VALUE}
TZ=${TZ_VALUE}
WEB_PORT=${WEB_PORT}
MEDIA_ROOT=${MEDIA_ROOT}
EOF

cat > /opt/namer/docker-compose.yml <<'EOF'
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

cat > /opt/namer/config/namer.cfg <<EOF
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
EOF

msg "Starting Namer"
docker compose --env-file /opt/namer/.env -f /opt/namer/docker-compose.yml up -d

IP_ADDR="$(hostname -I | awk '{print $1}')"

echo
printf 'Namer is running.\n'
printf 'Media root: %s\n' "$MEDIA_ROOT"
printf 'Config: %s\n' '/opt/namer/config/namer.cfg'
printf 'Web UI: http://%s:%s/\n' "$IP_ADDR" "$WEB_PORT"
printf 'Important: update_permissions_ownership is disabled by default for bind-mounted NAS paths in an unprivileged LXC.\n'
