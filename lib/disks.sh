#!/bin/bash

detect_disks() {
  header "Disk Discovery"
  info "Scanning available drives..."

  local os_device
  os_device=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | xargs basename)

  echo -e "${BOLD}Available drives:${NC}"
  echo "┌────────┬──────────┬──────────────────────────────┐"
  printf "│ %-6s │ %-8s │ %-28s │\n" "Device" "Size" "Model / Note"
  echo "├────────┼──────────┼──────────────────────────────┤"
  for dev in /dev/sd? /dev/nvme?n?; do
    [ -b "$dev" ] || continue
    local name
    name=$(basename "$dev")
    local size
    size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null)
    local model
    model=$(lsblk -dn -o MODEL "$dev" 2>/dev/null | xargs)
    local note=""
    if [ "$name" = "$os_device" ]; then
      note="← OS drive"
    fi
    printf "│ %-6s │ %-8s │ %-28s │\n" "$name" "$size" "$model $note"
  done
  echo "└────────┴──────────┴──────────────────────────────┘"
}

select_data_disk() {
  local os_device
  os_device=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | xargs basename)

  while true; do
    local choice
    choice=$(prompt_input "Select device for /data (apps + databases)" "")
    if [ -z "$choice" ]; then
      warn "Device cannot be empty"
      continue
    fi
    if [ "$choice" = "$os_device" ]; then
      warn "Cannot use the OS drive for /data"
      continue
    fi
    if [ ! -b "/dev/$choice" ]; then
      warn "Device /dev/$choice not found"
      continue
    fi
    DATA_DEVICE="/dev/$choice"
    ok "Selected $DATA_DEVICE for /data"
    break
  done
}

select_storage_disk() {
  while true; do
    local choice
    choice=$(prompt_input "Select device for /storage (media + photos, or 'skip')" "skip")
    [ "$choice" = "skip" ] && return
    if [ ! -b "/dev/$choice" ]; then
      warn "Device /dev/$choice not found"
      continue
    fi
    STORAGE_DEVICE="/dev/$choice"
    ok "Selected $STORAGE_DEVICE for /storage"
    break
  done
}

setup_lvm_and_mount() {
  local device="$1"
  local mount_point="$2"
  local vg_name
  vg_name=$(basename "$device")-vg

  if mountpoint -q "$mount_point"; then
    ok "$mount_point already mounted, skipping"
    return
  fi

  info "Setting up LVM on $device for $mount_point..."

  pvcreate "$device"
  vgcreate "$vg_name" "$device"
  lvcreate -l 80%FREE -n data "$vg_name"
  mkfs.ext4 "/dev/$vg_name/data"

  mkdir -p "$mount_point"

  local fstab_entry="/dev/$vg_name/data $mount_point ext4 defaults 0 2"
  if ! grep -qF "$mount_point" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak
    echo "$fstab_entry" >> /etc/fstab
  fi

  mount "$mount_point"

  ok "$mount_point ready (20% unallocated for future expansion)"
}

run_disk_setup() {
  detect_disks
  select_data_disk
  setup_lvm_and_mount "$DATA_DEVICE" "$DATA_DIR"
  mkdir -p "$DATA_DIR"/{databases,config,apps}

  select_storage_disk
  if [ -n "${STORAGE_DEVICE:-}" ]; then
    setup_lvm_and_mount "$STORAGE_DEVICE" "$STORAGE_DIR"
    mkdir -p "$STORAGE_DIR"/{media,torrents,photos,backups}
  fi

  chown -R "$(get_user):$(get_user)" "$DATA_DIR" 2>/dev/null || true
  chown -R "$(get_user):$(get_user)" "$STORAGE_DIR" 2>/dev/null || true
}
