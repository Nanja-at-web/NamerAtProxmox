#!/usr/bin/env bash
set -Eeuo pipefail

NAMER_PORT="${NAMER_PORT:-6980}"
PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-000}"
FAILED_DIR_NAME="${FAILED_DIR_NAME:-faild}"
DEST_DIR_NAME="${DEST_DIR_NAME:-dest}"
NAMER_IMAGE="${NAMER_IMAGE:-ghcr.io/theporndatabase/namer:latest}"
CONFIG_DIR="${CONFIG_DIR:-/opt/namer/config}"
MEDIA_DIR="${MEDIA_DIR:-/namer}"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $*"; }

export DEBIAN_FRONTEND=noninteractive

info "Updating base system"
apt-get update
apt-get upgrade -y

info "Installing Docker and tools"
apt-get install -y ca-certificates curl gnupg docker.io
systemctl enable --now docker

info "Preparing Namer directories"
mkdir -p "$CONFIG_DIR" "$MEDIA_DIR/watch" "$MEDIA_DIR/work" "$MEDIA_DIR/$FAILED_DIR_NAME" "$MEDIA_DIR/$DEST_DIR_NAME"
chmod -R 775 "$MEDIA_DIR" || true

if [[ ! -f "$CONFIG_DIR/namer.cfg" ]]; then
  info "Creating default namer.cfg"
  curl -fsSL https://raw.githubusercontent.com/ThePornDatabase/namer/main/namer/namer.cfg.default -o "$CONFIG_DIR/namer.cfg"
  sed -i \
    -e 's|^porndb_token =.*|porndb_token = CHANGE_ME|' \
    -e 's|^watch_dir =.*|watch_dir = /media/watch|' \
    -e 's|^work_dir =.*|work_dir = /media/work|' \
    -e "s|^failed_dir =.*|failed_dir = /media/$FAILED_DIR_NAME|" \
    -e "s|^dest_dir =.*|dest_dir = /media/$DEST_DIR_NAME|" \
    -e 's|^web =.*|web = True|' \
    -e "s|^port =.*|port = $NAMER_PORT|" \
    -e 's|^host =.*|host = 0.0.0.0|' \
    "$CONFIG_DIR/namer.cfg"
else
  info "Keeping existing $CONFIG_DIR/namer.cfg"
fi

info "Creating systemd service"
cat >/etc/systemd/system/namer.service <<EOF
[Unit]
Description=Namer Docker container
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker rm -f namer
ExecStart=/usr/bin/docker run --name namer --pull always \
  -p ${NAMER_PORT}:${NAMER_PORT} \
  -e PUID=${PUID} \
  -e PGID=${PGID} \
  -e UMASK=${UMASK} \
  -v ${CONFIG_DIR}:/config \
  -v ${MEDIA_DIR}:/media \
  ${NAMER_IMAGE}
ExecStop=/usr/bin/docker stop namer
ExecStopPost=-/usr/bin/docker rm -f namer

[Install]
WantedBy=multi-user.target
EOF

info "Pulling Namer image"
docker pull "$NAMER_IMAGE"

info "Starting Namer"
systemctl daemon-reload
systemctl enable --now namer.service

ok "Namer installed. Edit $CONFIG_DIR/namer.cfg and set porndb_token before production use."
