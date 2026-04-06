#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Script failed on line ${LINENO}." >&2' ERR

if ! command -v pct >/dev/null 2>&1; then
  echo "This script must be run on a Proxmox VE host." >&2
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

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "$name must not be empty." >&2
    exit 1
  fi
}

msg() {
  echo
  echo "==> $*"
}

find_debian_template() {
  pveam available --section system | awk '/debian-12-standard.*amd64/ {print $2}' | tail -n1
}

CTID="$(ask 'CT ID' '115')"
HOSTNAME_VALUE="$(ask 'CT hostname' 'namer')"
STORAGE="$(ask 'Container storage' 'local-lvm')"
TEMPLATE_STORAGE="$(ask 'Template storage' 'local')"
BRIDGE="$(ask 'Network bridge' 'vmbr0')"
DISK_GB="$(ask 'Disk size in GB' '8')"
CORES="$(ask 'CPU cores' '2')"
MEMORY="$(ask 'Memory in MB' '2048')"
HOST_BIND_PATH="$(ask 'Host bind mount path (mounted on Proxmox host)' '/mnt/bindmounts/qnap-namer')"
CT_BIND_PATH="$(ask 'Container mount path' '/mnt/namer-share')"
APP_API_TOKEN="$(ask 'Application API token')"
TZ_VALUE="$(ask 'Timezone' 'Europe/Berlin')"
PUID_VALUE="$(ask 'Docker PUID' '1000')"
PGID_VALUE="$(ask 'Docker PGID' '1000')"
WEB_PORT="$(ask 'Namer web port' '6980')"

for pair in \
  "CTID:$CTID" \
  "HOSTNAME_VALUE:$HOSTNAME_VALUE" \
  "STORAGE:$STORAGE" \
  "TEMPLATE_STORAGE:$TEMPLATE_STORAGE" \
  "BRIDGE:$BRIDGE" \
  "HOST_BIND_PATH:$HOST_BIND_PATH" \
  "CT_BIND_PATH:$CT_BIND_PATH" \
  "APP_API_TOKEN:$APP_API_TOKEN"; do
  require_value "${pair%%:*}" "${pair#*:}"
done

if pct status "$CTID" >/dev/null 2>&1; then
  echo "CTID $CTID already exists." >&2
  exit 1
fi

if [[ ! -d "$HOST_BIND_PATH" ]]; then
  echo "Host bind path does not exist: $HOST_BIND_PATH" >&2
  echo "Mount your NAS share on the Proxmox host first, then rerun this script." >&2
  exit 1
fi

for d in watch work failed DESTINATION; do
  mkdir -p "$HOST_BIND_PATH/$d"
done

msg "Updating template index"
pveam update >/dev/null
TEMPLATE_NAME="$(find_debian_template)"
if [[ -z "$TEMPLATE_NAME" ]]; then
  echo "No Debian 12 template found via pveam." >&2
  exit 1
fi

if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $2}' | grep -qx "$TEMPLATE_NAME"; then
  msg "Downloading template $TEMPLATE_NAME"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
fi

TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}"

msg "Creating unprivileged Docker LXC"
pct create "$CTID" "$TEMPLATE_PATH" \
  --hostname "$HOSTNAME_VALUE" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap 512 \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp,type=veth" \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --onboot 1 \
  --startup order=20 \
  --ostype debian \
  --mp0 "${HOST_BIND_PATH},mp=${CT_BIND_PATH}"

msg "Starting container"
pct start "$CTID"
sleep 5

INSTALLER_PATH="/tmp/namer-install-standalone.sh"
cat > "$INSTALLER_PATH" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[ERROR] Installation failed on line ${LINENO}." >&2' ERR
if [[ ${EUID} -ne 0 ]]; then
  echo "Please run this script as root inside the container." >&2
  exit 1
fi
MEDIA_ROOT="__MEDIA_ROOT__"
APP_API_TOKEN="__APP_API_TOKEN__"
TZ_VALUE="__TZ_VALUE__"
PUID_VALUE="__PUID_VALUE__"
PGID_VALUE="__PGID_VALUE__"
WEB_PORT="__WEB_PORT__"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates
for d in watch work failed DESTINATION; do
  mkdir -p "$MEDIA_ROOT/$d"
done
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
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
porndb_token = ${APP_API_TOKEN}
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
docker compose --env-file /opt/namer/.env -f /opt/namer/docker-compose.yml up -d
EOS

sed -i "s|__MEDIA_ROOT__|${CT_BIND_PATH}|g" "$INSTALLER_PATH"
sed -i "s|__APP_API_TOKEN__|${APP_API_TOKEN}|g" "$INSTALLER_PATH"
sed -i "s|__TZ_VALUE__|${TZ_VALUE}|g" "$INSTALLER_PATH"
sed -i "s|__PUID_VALUE__|${PUID_VALUE}|g" "$INSTALLER_PATH"
sed -i "s|__PGID_VALUE__|${PGID_VALUE}|g" "$INSTALLER_PATH"
sed -i "s|__WEB_PORT__|${WEB_PORT}|g" "$INSTALLER_PATH"
chmod +x "$INSTALLER_PATH"

msg "Pushing installer into container"
pct push "$CTID" "$INSTALLER_PATH" /root/namer-install-standalone.sh -perms 755

msg "Running installer inside container"
pct exec "$CTID" -- bash /root/namer-install-standalone.sh

IP_ADDR="$(pct exec "$CTID" -- hostname -I | awk '{print $1}')"

echo
echo "Namer CT created successfully."
echo "Container ID: $CTID"
echo "Host bind path: $HOST_BIND_PATH"
echo "Container bind path: $CT_BIND_PATH"
echo "Web UI: http://${IP_ADDR}:${WEB_PORT}/"
echo ""
echo "Architecture: NAS host mount -> LXC bind mount -> Docker bind mount -> /media"
