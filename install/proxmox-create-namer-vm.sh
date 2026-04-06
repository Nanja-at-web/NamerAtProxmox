#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Script failed on line ${LINENO}" >&2' ERR

if ! command -v qm >/dev/null 2>&1; then
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

validate_storage() {
  local storage="$1"
  if ! pvesm status --storage "$storage" >/dev/null 2>&1; then
    echo "Storage '$storage' not found." >&2
    exit 1
  fi
}

msg() {
  echo
  echo "==> $*"
}

msg "Namer VM installer for Proxmox VE"

VMID="$(ask 'VM ID' '9120')"
VM_NAME="$(ask 'VM name' 'namer-vm')"
STORAGE="$(ask 'VM disk storage' 'local-lvm')"
SNIPPET_STORAGE="$(ask 'Cloud-init snippet storage' 'local')"
BRIDGE="$(ask 'Network bridge' 'vmbr0')"
CORES="$(ask 'CPU cores' '2')"
MEMORY="$(ask 'Memory in MB' '2048')"
DISK_GB="$(ask 'Disk size in GB' '32')"
CI_USER="$(ask 'Cloud-init username' 'namer')"
CI_PASSWORD="$(ask 'Password for the VM user')"
QNAP_IP="$(ask 'QNAP IP address')"
QNAP_SHARE="$(ask 'QNAP share name' 'namer')"
QNAP_USER="$(ask 'QNAP SMB username')"
QNAP_PASS="$(ask 'QNAP SMB password')"
TPDB_TOKEN="$(ask 'ThePornDB API token')"
TZ_VALUE="$(ask 'Timezone' 'Europe/Berlin')"
PUID_VALUE="$(ask 'Docker PUID' '1000')"
PGID_VALUE="$(ask 'Docker PGID' '1000')"
WEB_PORT="$(ask 'Namer web port' '6980')"

for pair in \
  "VMID:$VMID" \
  "VM_NAME:$VM_NAME" \
  "STORAGE:$STORAGE" \
  "SNIPPET_STORAGE:$SNIPPET_STORAGE" \
  "BRIDGE:$BRIDGE" \
  "CI_USER:$CI_USER" \
  "CI_PASSWORD:$CI_PASSWORD" \
  "QNAP_IP:$QNAP_IP" \
  "QNAP_SHARE:$QNAP_SHARE" \
  "QNAP_USER:$QNAP_USER" \
  "QNAP_PASS:$QNAP_PASS" \
  "TPDB_TOKEN:$TPDB_TOKEN"; do
  require_value "${pair%%:*}" "${pair#*:}"
done

validate_storage "$STORAGE"
validate_storage "$SNIPPET_STORAGE"

if qm status "$VMID" >/dev/null 2>&1; then
  echo "VMID $VMID already exists." >&2
  exit 1
fi

WORKDIR="/var/lib/vz/template/qemu"
IMG_NAME="debian-12-genericcloud-amd64.qcow2"
IMG_PATH="${WORKDIR}/${IMG_NAME}"
SNIPPET_DIR="/var/lib/vz/snippets"
USERDATA_PATH="${SNIPPET_DIR}/${VM_NAME}-user-data.yaml"

mkdir -p "$WORKDIR" "$SNIPPET_DIR"

if [[ ! -f "$IMG_PATH" ]]; then
  msg "Downloading Debian 12 cloud image"
  wget -qO "$IMG_PATH" "https://cloud.debian.org/images/cloud/bookworm/latest/${IMG_NAME}"
fi

msg "Creating cloud-init user-data"
cat > "$USERDATA_PATH" <<EOF
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
package_update: true
package_upgrade: true
users:
  - default
  - name: ${CI_USER}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: '${CI_PASSWORD}'
write_files:
  - path: /root/.smbcredentials-namer
    permissions: '0600'
    content: |
      username=${QNAP_USER}
      password=${QNAP_PASS}
  - path: /opt/namer/.env
    permissions: '0644'
    content: |
      PUID=${PUID_VALUE}
      PGID=${PGID_VALUE}
      TZ=${TZ_VALUE}
      WEB_PORT=${WEB_PORT}
  - path: /opt/namer/docker-compose.yml
    permissions: '0644'
    content: |
      services:
        namer:
          container_name: namer
          image: ghcr.io/theporndatabase/namer:latest
          environment:
            PUID: \${PUID}
            PGID: \${PGID}
            TZ: \${TZ}
            NAMER_CONFIG: /config/namer.cfg
          ports:
            - "\${WEB_PORT}:6980"
          volumes:
            - /opt/namer/config:/config
            - /mnt/qnap/namer:/media
          restart: unless-stopped
  - path: /opt/namer/config/namer.cfg
    permissions: '0644'
    content: |
      [namer]
      porndb_token = ${TPDB_TOKEN}
      prefer_dir_name_if_available = True
      min_file_size = 300
      write_namer_log = False
      write_namer_failed_log = True
      target_extensions = mp4,mkv,avi,mov,flv
      update_permissions_ownership = True
      set_dir_permissions = 775
      set_file_permissions = 664
      set_uid = ${PUID_VALUE}
      set_gid = ${PGID_VALUE}
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
packages:
  - qemu-guest-agent
  - curl
  - wget
  - ca-certificates
  - cifs-utils
runcmd:
  - mkdir -p /mnt/qnap/namer /opt/namer/config
  - sh -c 'echo "//${QNAP_IP}/${QNAP_SHARE} /mnt/qnap/namer cifs credentials=/root/.smbcredentials-namer,iocharset=utf8,uid=${PUID_VALUE},gid=${PGID_VALUE},file_mode=0664,dir_mode=0775,nofail,x-systemd.automount,_netdev 0 0" >> /etc/fstab'
  - mount -a
  - mkdir -p /mnt/qnap/namer/watch /mnt/qnap/namer/work /mnt/qnap/namer/failed /mnt/qnap/namer/DESTINATION
  - sh -c 'curl -fsSL https://get.docker.com | sh'
  - usermod -aG docker ${CI_USER}
  - systemctl enable --now docker
  - docker compose --env-file /opt/namer/.env -f /opt/namer/docker-compose.yml up -d
  - systemctl enable --now qemu-guest-agent
final_message: |
  Namer installation completed.
  Web UI: http://VM-IP:${WEB_PORT}/
EOF

msg "Creating VM"
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --agent 1 \
  --ostype l26 \
  --serial0 socket \
  --vga serial0

msg "Importing disk"
qm importdisk "$VMID" "$IMG_PATH" "$STORAGE"

IMPORTED_DISK="$(qm config "$VMID" | awk -F': ' '/^unused[0-9]+: / {print $2; exit}')"
if [[ -z "$IMPORTED_DISK" ]]; then
  echo "Unable to determine imported disk for VM $VMID." >&2
  exit 1
fi

qm set "$VMID" --scsihw virtio-scsi-pci --scsi0 "$IMPORTED_DISK"
qm set "$VMID" --boot order=scsi0
qm resize "$VMID" scsi0 "${DISK_GB}G"
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --ipconfig0 ip=dhcp
qm set "$VMID" --ciuser "$CI_USER"
qm set "$VMID" --cipassword "$CI_PASSWORD"
qm set "$VMID" --cicustom "user=${SNIPPET_STORAGE}:snippets/$(basename "$USERDATA_PATH")"

msg "Starting VM"
qm start "$VMID"

echo
echo "VM $VM_NAME ($VMID) was created and started."
echo "Cloud-init file: $USERDATA_PATH"
echo "Open the Proxmox console and wait for cloud-init to finish."
echo "Then access Namer at: http://<VM-IP>:${WEB_PORT}/"
