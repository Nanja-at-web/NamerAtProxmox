#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-/var/log/namer-install.log}"
NAMER_PORT="${NAMER_PORT:-6980}"
PORNDB_TOKEN="${PORNDB_TOKEN:-${TPDB_TOKEN:-}}"
PUID="${PUID:-99}"
PGID="${PGID:-100}"
UMASK="${UMASK:-000}"
FAILED_DIR_NAME="${FAILED_DIR_NAME:-faild}"
DEST_DIR_NAME="${DEST_DIR_NAME:-dest}"
NAMER_INSTALL_MODE="${NAMER_INSTALL_MODE:-source}"
NAMER_SOURCE_REPO="${NAMER_SOURCE_REPO:-Nanja-at-web/namer}"
NAMER_SOURCE_REF="${NAMER_SOURCE_REF:-codex/matching-cleanup-review-db}"
NAMER_IMAGE="${NAMER_IMAGE:-local/namer:${NAMER_SOURCE_REF//\//-}}"
NAMER_CONFIG_URL="${NAMER_CONFIG_URL:-https://raw.githubusercontent.com/${NAMER_SOURCE_REPO}/${NAMER_SOURCE_REF}/namer/namer.cfg.default}"
NAMER_SRC_DIR="${NAMER_SRC_DIR:-/opt/namer/src}"
CONFIG_DIR="${CONFIG_DIR:-/opt/namer/config}"
MEDIA_DIR="${MEDIA_DIR:-/namer}"
NAMER_MEDIA_MOUNT="${NAMER_MEDIA_MOUNT:-/namer}"

INFO_COLOR=$'\033[1;34m'
OK_COLOR=$'\033[1;32m'
ERROR_COLOR=$'\033[1;31m'
RESET_COLOR=$'\033[0m'
CLEAR_LINE=$'\r\033[2K'

info() { echo -e "${INFO_COLOR}[INFO]${RESET_COLOR} $*"; }
ok() { echo -e "${OK_COLOR}[OK]${RESET_COLOR} $*"; }

msg_info() { echo -ne "${INFO_COLOR}[INFO]${RESET_COLOR} $*..."; }
msg_ok() { echo -e "${CLEAR_LINE}${OK_COLOR}[OK]${RESET_COLOR} $*"; }
msg_fail() {
  echo -e "${CLEAR_LINE}${ERROR_COLOR}[ERROR]${RESET_COLOR} $*" >&2
  echo "Log: $LOG_FILE" >&2
  tail -n 100 "$LOG_FILE" >&2 || true
  exit 1
}

run_quiet() {
  local label="$1"
  shift
  msg_info "$label"
  if "$@" >>"$LOG_FILE" 2>&1; then
    msg_ok "$label"
  else
    msg_fail "$label"
  fi
}

run_stream() {
  local label="$1"
  shift
  msg_info "$label"
  echo
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    msg_ok "$label"
  else
    msg_fail "$label"
  fi
}

write_namer_diagnostics() {
  {
    echo
    echo "---- systemctl status namer ----"
    systemctl status namer --no-pager || true
    echo
    echo "---- docker ps -a ----"
    docker ps -a || true
    echo
    echo "---- journalctl -u namer -n 160 ----"
    journalctl -u namer -n 160 --no-pager || true
  } >>"$LOG_FILE" 2>&1
}

wait_for_namer_webui() {
  msg_info "Waiting for Namer WebUI"
  for _ in {1..45}; do
    if docker inspect -f '{{.State.Running}}' namer >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:${NAMER_PORT}/" >/dev/null 2>&1; then
      msg_ok "Namer WebUI is reachable"
      return 0
    fi
    sleep 2
  done

  write_namer_diagnostics
  msg_fail "Namer WebUI did not become reachable. Check porndb_token and service logs."
}

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

cat >"$LOG_FILE" <<EOF
Namer container installation log
Started: $(date -Is)
Mode: $NAMER_INSTALL_MODE
Source: ${NAMER_SOURCE_REPO}@${NAMER_SOURCE_REF}
Image: $NAMER_IMAGE
EOF

run_quiet "Updating package index" apt-get update

run_quiet "Installing Docker and tools" apt-get install -y ca-certificates curl git gnupg docker.io
run_quiet "Enabling Docker service" systemctl enable --now docker

msg_info "Preparing Namer directories"
mkdir -p "$CONFIG_DIR" "$MEDIA_DIR/watch" "$MEDIA_DIR/work" "$MEDIA_DIR/$FAILED_DIR_NAME" "$MEDIA_DIR/$DEST_DIR_NAME"
chmod 775 "$MEDIA_DIR" "$MEDIA_DIR/watch" "$MEDIA_DIR/work" "$MEDIA_DIR/$FAILED_DIR_NAME" "$MEDIA_DIR/$DEST_DIR_NAME" 2>/dev/null || true
msg_ok "Prepared Namer directories"

if [[ ! -f "$CONFIG_DIR/namer.cfg" ]]; then
  msg_info "Creating default namer.cfg"
  curl -fsSL "$NAMER_CONFIG_URL" -o "$CONFIG_DIR/namer.cfg" >>"$LOG_FILE" 2>&1 || msg_fail "Creating default namer.cfg"
  sed -i \
    -e "s|^porndb_token =.*|porndb_token = ${PORNDB_TOKEN:-CHANGE_ME}|" \
    -e "s|^watch_dir =.*|watch_dir = $NAMER_MEDIA_MOUNT/watch|" \
    -e "s|^work_dir =.*|work_dir = $NAMER_MEDIA_MOUNT/work|" \
    -e "s|^failed_dir =.*|failed_dir = $NAMER_MEDIA_MOUNT/$FAILED_DIR_NAME|" \
    -e "s|^dest_dir =.*|dest_dir = $NAMER_MEDIA_MOUNT/$DEST_DIR_NAME|" \
    -e 's|^web =.*|web = True|' \
    -e "s|^port =.*|port = $NAMER_PORT|" \
    -e 's|^host =.*|host = 0.0.0.0|' \
    -e 's|^update_permissions_ownership =.*|update_permissions_ownership = False|' \
    -e 's|^set_uid =.*|set_uid =|' \
    -e 's|^set_gid =.*|set_gid =|' \
    -e 's|^database_path =.*|database_path = /config/database|' \
    -e 's|^use_database =.*|use_database = True|' \
    -e 's|^cleanup_enabled =.*|cleanup_enabled = True|' \
    -e 's|^review_database_enabled =.*|review_database_enabled = True|' \
    -e 's|^review_database_path =.*|review_database_path = /config/database/review.sqlite|' \
    "$CONFIG_DIR/namer.cfg" >>"$LOG_FILE" 2>&1 || msg_fail "Creating default namer.cfg"
  msg_ok "Created default namer.cfg"
else
  info "Keeping existing $CONFIG_DIR/namer.cfg"
fi

DOCKER_PULL_POLICY="always"
if [[ "$NAMER_INSTALL_MODE" == "source" ]]; then
  msg_info "Preparing Namer source ${NAMER_SOURCE_REPO}@${NAMER_SOURCE_REF}"
  if [[ -d "$NAMER_SRC_DIR/.git" ]]; then
    git -C "$NAMER_SRC_DIR" fetch --depth 1 origin "$NAMER_SOURCE_REF" >>"$LOG_FILE" 2>&1 || msg_fail "Preparing Namer source"
    git -C "$NAMER_SRC_DIR" checkout -B build FETCH_HEAD >>"$LOG_FILE" 2>&1 || msg_fail "Preparing Namer source"
    git -C "$NAMER_SRC_DIR" submodule update --init --recursive --depth 1 >>"$LOG_FILE" 2>&1 || msg_fail "Preparing Namer source"
  elif [[ -e "$NAMER_SRC_DIR" ]]; then
    msg_fail "$NAMER_SRC_DIR exists but is not a git checkout."
  else
    mkdir -p "$(dirname "$NAMER_SRC_DIR")"
    git clone --depth 1 --recurse-submodules --shallow-submodules --branch "$NAMER_SOURCE_REF" "https://github.com/${NAMER_SOURCE_REPO}.git" "$NAMER_SRC_DIR" >>"$LOG_FILE" 2>&1 || msg_fail "Preparing Namer source"
  fi
  msg_ok "Prepared Namer source"
  run_stream "Building Namer Docker image" docker build --progress plain --pull -t "$NAMER_IMAGE" "$NAMER_SRC_DIR"
  DOCKER_PULL_POLICY="never"
elif [[ "$NAMER_INSTALL_MODE" == "image" ]]; then
  run_quiet "Pulling Namer image" docker pull "$NAMER_IMAGE"
else
  echo "[ERROR] NAMER_INSTALL_MODE must be 'source' or 'image'." >&2
  exit 1
fi

msg_info "Creating systemd service"
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
ExecStart=/usr/bin/docker run --name namer --pull ${DOCKER_PULL_POLICY} \
  --log-driver=journald \
  -p ${NAMER_PORT}:${NAMER_PORT} \
  -e PUID=${PUID} \
  -e PGID=${PGID} \
  -e UMASK=${UMASK} \
  -v ${CONFIG_DIR}:/config \
  -v ${MEDIA_DIR}:${NAMER_MEDIA_MOUNT} \
  ${NAMER_IMAGE}
ExecStop=/usr/bin/docker stop namer

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created systemd service"

run_quiet "Reloading systemd" systemctl daemon-reload
run_quiet "Starting Namer service" systemctl enable --now namer.service
wait_for_namer_webui

ok "Namer installed and WebUI is reachable."
