#!/usr/bin/env bash
# Copyright (c) 2026 Nanja-at-web
# License: MIT
# Source: https://github.com/ThePornDatabase/namer | https://api.theporndb.net/docs

if [[ -n "${FUNCTIONS_FILE_PATH:-}" ]]; then
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os
else
  export DEBIAN_FRONTEND=noninteractive
  STD=""
  msg_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
  msg_ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
  motd_ssh() { :; }
  customize() { :; }
  cleanup_lxc() { :; }
  apt-get update
fi

msg_info "Installing Dependencies"
$STD apt-get install -y \
  cifs-utils \
  curl \
  python3 \
  python3-venv
msg_ok "Installed Dependencies"

msg_info "Creating Namer User and Directories"
getent group namer >/dev/null || groupadd --system namer
getent passwd namer >/dev/null || useradd --system --gid namer --home-dir /opt/namer --shell /usr/sbin/nologin namer
mkdir -p /opt/namer/config /namer/{watch,work,failed,dest} /etc/namer
ln -sfn /namer/failed /namer/faild
chown -R namer:namer /opt/namer /namer
chmod 0775 /opt/namer /opt/namer/config /namer /namer/{watch,work,failed,dest}
msg_ok "Created Namer User and Directories"

msg_info "Installing Namer"
python3 -m venv /opt/namer/venv
$STD /opt/namer/venv/bin/python -m pip install --upgrade pip wheel
$STD /opt/namer/venv/bin/python -m pip install --upgrade namer
chown -R namer:namer /opt/namer
msg_ok "Installed Namer"

msg_info "Creating QNAP Mount Configuration"
cat >/etc/namer/qnap.env <<'ENVEOF'
# QNAP SMB/CIFS mount used by namer-mount.service.
# The default requested by this container is //192.168.1.24/namer mounted at /namer.
QNAP_IP="192.168.1.24"
QNAP_SHARE="namer"
QNAP_MOUNT="/namer"
# Leave QNAP_USER empty for guest access. Set QNAP_USER and QNAP_PASSWORD for authenticated shares.
QNAP_USER=""
QNAP_PASSWORD=""
QNAP_DOMAIN="WORKGROUP"
QNAP_OPTIONS="rw,iocharset=utf8,vers=2.0,file_mode=0777,dir_mode=0777,noperm"
ENVEOF
chmod 0600 /etc/namer/qnap.env
cat >/usr/local/sbin/namer-mount-qnap <<'SCRIPTEOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/namer/qnap.env
mkdir -p "$QNAP_MOUNT"
if mountpoint -q "$QNAP_MOUNT"; then
  exit 0
fi
opts="$QNAP_OPTIONS"
if [[ -n "${QNAP_USER:-}" ]]; then
  cred_file="/run/namer-qnap-credentials"
  umask 077
  {
    echo "username=$QNAP_USER"
    echo "password=$QNAP_PASSWORD"
    echo "domain=${QNAP_DOMAIN:-WORKGROUP}"
  } >"$cred_file"
  opts="$opts,credentials=$cred_file"
else
  opts="$opts,guest"
fi
mount -t cifs "//${QNAP_IP}/${QNAP_SHARE}" "$QNAP_MOUNT" -o "$opts"
mkdir -p "$QNAP_MOUNT"/{watch,work,failed,dest}
ln -sfn "$QNAP_MOUNT/failed" "$QNAP_MOUNT/faild"
SCRIPTEOF
chmod 0755 /usr/local/sbin/namer-mount-qnap
cat >/etc/systemd/system/namer-mount.service <<'EOFUNIT'
[Unit]
Description=Mount QNAP Namer Share
Wants=network-online.target
After=network-online.target
Before=namer.service

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/namer/qnap.env
ExecStart=/usr/local/sbin/namer-mount-qnap
ExecStop=/bin/umount /namer

[Install]
WantedBy=multi-user.target
EOFUNIT
msg_ok "Created QNAP Mount Configuration"

msg_info "Creating Namer Configuration"
if [[ ! -f /opt/namer/config/namer.cfg ]]; then
  curl -fsSL https://raw.githubusercontent.com/ThePornDatabase/namer/main/namer/namer.cfg.default -o /opt/namer/config/namer.cfg || true
  if [[ ! -s /opt/namer/config/namer.cfg ]]; then
    cat >/opt/namer/config/namer.cfg <<'CFGEOF'
[Watchdog]
watch_dir = /namer/watch
work_dir = /namer/work
failed_dir = /namer/failed
dest_dir = /namer/dest

[Web]
web = True
port = 6980
host = 0.0.0.0

[ThePornDB]
porndb_token = CHANGE_ME
CFGEOF
  else
    sed -i \
      -e 's#^watch_dir *=.*#watch_dir = /namer/watch#' \
      -e 's#^work_dir *=.*#work_dir = /namer/work#' \
      -e 's#^failed_dir *=.*#failed_dir = /namer/failed#' \
      -e 's#^dest_dir *=.*#dest_dir = /namer/dest#' \
      -e 's#^web *=.*#web = True#' \
      -e 's#^port *=.*#port = 6980#' /opt/namer/config/namer.cfg || true
  fi
fi
chown -R namer:namer /opt/namer/config
chmod 0640 /opt/namer/config/namer.cfg
msg_ok "Created Namer Configuration"

msg_info "Creating Service"
cat >/etc/systemd/system/namer.service <<'EOFUNIT'
[Unit]
Description=Namer Watchdog and Web UI
Wants=network-online.target namer-mount.service
After=network-online.target namer-mount.service

[Service]
Type=simple
User=namer
Group=namer
WorkingDirectory=/opt/namer/config
Environment=HOME=/opt/namer/config
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/namer/venv/bin/python -m namer watchdog
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFUNIT
systemctl enable -q namer-mount.service
systemctl enable -q --now namer.service
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
