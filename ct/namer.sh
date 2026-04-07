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
  pct exec "$target_ctid" -- env \
    NAMER_MEDIA_ROOT=/mnt/namer-share \
    NAMER_WEB_PORT=6980 \
    bash -lc 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-community.sh)"'
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