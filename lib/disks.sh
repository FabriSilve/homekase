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

setup_disk_and_mount() {
  local device="$1"
  local mount_point="$2"

  if mountpoint -q "$mount_point"; then
    ok "$mount_point already mounted, skipping"
    return
  fi

  # Show existing data on disk for safety
  warn "Current state of $device:"
  lsblk -f "$device" 2>/dev/null || true

  local strategy
  strategy=$(prompt_choose "How do you want to set up $device for $mount_point?" \
    "partition — Create a new partition (keeps existing data)" \
    "erase — Wipe entire disk and use LVM" \
    "skip — Don't set up $mount_point")

  case "$strategy" in
    partition*) setup_partition_and_mount "$device" "$mount_point" ;;
    erase*)     setup_lvm_and_mount "$device" "$mount_point" ;;
    skip*)      warn "Skipped $mount_point setup"; return 0 ;;
  esac
}

setup_partition_and_mount() {
  local device="$1"
  local mount_point="$2"

  info "Creating new partition on $device for $mount_point..."

  # Find next available partition number
  local last_part_num
  last_part_num=$(lsblk -ln -o NAME "$device" | grep -oP '\d+$' | sort -n | tail -1)
  local new_part_num=$(( ${last_part_num:-0} + 1 ))

  local free_space
  free_space=$(parted -s "$device" unit GB print free 2>/dev/null | awk '/Free Space/ {size=$3} END {print size}')
  info "Available free space: ${free_space:-unknown}"

  if ! prompt_yes_no "Create new partition #${new_part_num} using remaining free space?"; then
    warn "Partition creation aborted for $device"
    return 1
  fi

  # Create partition in remaining free space
  parted -s "$device" mkpart primary ext4 0% 100% 2>/dev/null || \
  parted -s -a optimal "$device" -- mkpart primary ext4 -0 -1 || {
    error "Failed to create partition. You may need to do this manually."
    return 1
  }

  # Detect new partition path (handles both sdX1 and nvme0n1p1 naming)
  local new_part
  if [[ "$device" == *nvme* ]]; then
    new_part="${device}p${new_part_num}"
  else
    new_part="${device}${new_part_num}"
  fi

  # Wait for partition to appear
  sleep 1
  partprobe "$device" 2>/dev/null || true

  if [ ! -b "$new_part" ]; then
    error "Partition $new_part not found after creation"
    return 1
  fi

  info "Formatting $new_part as ext4..."
  mkfs.ext4 -q "$new_part"

  mkdir -p "$mount_point"

  local fstab_entry="$new_part $mount_point ext4 defaults 0 2"
  if ! grep -qF "$mount_point" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak
    echo "$fstab_entry" >> /etc/fstab
  fi

  mount "$mount_point"
  ok "$mount_point ready on $new_part"
}

setup_lvm_and_mount() {
  local device="$1"
  local mount_point="$2"
  local vg_name
  vg_name=$(basename "$device")-vg

  info "Setting up LVM on $device for $mount_point..."
  info "LVM will use 80% of disk space, leaving 20% unallocated for future expansion."

  if ! prompt_yes_no "This will ERASE ALL DATA on $device. Continue?" "n"; then
    warn "Disk setup aborted for $device"
    return 1
  fi

  if ! pvcreate -f "$device"; then
    error "pvcreate failed on $device — disk may have existing partitions or LVM signatures"
    warn "Run 'wipefs -a $device' manually if you want to force it"
    return 1
  fi
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
  setup_disk_and_mount "$DATA_DEVICE" "$DATA_DIR"
  mkdir -p "$DATA_DIR"/{databases,config,apps} 2>/dev/null || true

  select_storage_disk
  if [ -n "${STORAGE_DEVICE:-}" ]; then
    setup_disk_and_mount "$STORAGE_DEVICE" "$STORAGE_DIR"
    mkdir -p "$STORAGE_DIR"/{media,torrents,photos,backups} 2>/dev/null || true
  fi

  chown -R "$(get_user):$(get_user)" "$DATA_DIR" 2>/dev/null || true
  chown -R "$(get_user):$(get_user)" "$STORAGE_DIR" 2>/dev/null || true
}
