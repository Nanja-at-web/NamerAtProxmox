#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2026 community-scripts ORG
# Author: OpenAI
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/theporndatabase/namer

APP="Namer"
var_tags="${var_tags:-media;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

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

start
build_container

msg_info "Running Namer installer inside CT $CTID"
if pct exec "$CTID" -- bash -lc 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/Nanja-at-web/NamerAtProxmox/main/install/namer-install-community.sh)"'; then
  msg_ok "Namer installed successfully in CT $CTID"
else
  msg_error "Namer installer failed in CT $CTID"
  exit 1
fi

description
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6980${CL}"
echo -e "${INFO}${YW} Recommended library mount inside the container:${CL}"
echo -e "${TAB}${BGN}/mnt/namer-share${CL}"
