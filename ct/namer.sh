#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/test/nfs-v1-autark-installer/misc/build.func)
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

stage_ct_install_env() {
  msg_info "Writing install environment into CT ${CTID}"

  pct exec "$CTID" -- bash -lc "cat >/root/namer-install.env <<EOF
NAMER_MEDIA_ROOT=${CT_MOUNT}
NAMER_TPDB_TOKEN=${TPDB_TOKEN}
NAMER_WATCH_DIR=/media/watch
NAMER_WORK_DIR=/media/work
NAMER_FAILED_DIR=/media/failed
NAMER_DEST_DIR=/media/dest
NAMER_WEB_PORT=6980
NAMER_WEB_HOST=0.0.0.0
NAMER_WEB_ENABLED=True
NAMER_UPDATE_PERMISSIONS_OWNERSHIP=False
EOF
chmod 600 /root/namer-install.env"

  msg_ok "Install environment staged in CT"
}

pre_install_hook() {
  attach_mount_to_ct
  run_host_mount_check
  stage_ct_install_env
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

  unset TPDB_TOKEN

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
