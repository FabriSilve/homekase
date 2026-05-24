#!/bin/bash

detect_disks() {
  header "Disk Discovery"
  info "Scanning available drives..."

  local os_device
  os_device=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | xargs basename)

  echo -e "${BOLD}Available drives:${NC}"
  echo "┌─────────┬──────────┬──────────────────────────────┐"
  printf "│ %-7s │ %-8s │ %-28s │\n" "Device" "Size" "Model / Note"
  echo "├─────────┼──────────┼──────────────────────────────┤"
  for dev in /dev/sd? /dev/nvme?n?; do
    [ -b "$dev" ] || continue
    local name size model note=""
    name=$(basename "$dev")
    size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null)
    model=$(lsblk -dn -o MODEL "$dev" 2>/dev/null | xargs)
    if [ "$name" = "$os_device" ]; then
      note="← OS drive"
    fi
    printf "│ %-7s │ %-8s │ %-28s │\n" "$name" "$size" "$model $note"
  done
  echo "└─────────┴──────────┴──────────────────────────────┘"

  # Show LVM info if any VGs exist
  if command -v vgs >/dev/null 2>&1 && vgs --noheadings 2>/dev/null | grep -q .; then
    echo ""
    echo -e "${BOLD}LVM volume groups:${NC}"
    echo "┌──────────────┬──────────┬──────────┐"
    printf "│ %-12s │ %-8s │ %-8s │\n" "VG Name" "Size" "Free"
    echo "├──────────────┼──────────┼──────────┤"
    while IFS= read -r line; do
      local vg_name vg_size vg_free
      vg_name=$(echo "$line" | awk '{print $1}')
      vg_size=$(echo "$line" | awk '{print $6}')
      vg_free=$(echo "$line" | awk '{print $7}')
      printf "│ %-12s │ %-8s │ %-8s │\n" "$vg_name" "$vg_size" "$vg_free"
    done < <(vgs --noheadings 2>/dev/null)
    echo "└──────────────┴──────────┴──────────┘"
  fi
}

select_disk() {
  local purpose="$1"
  local var_name="$2"
  local default_skip="${3:-}"

  while true; do
    local choice
    if [ -n "$default_skip" ]; then
      choice=$(prompt_input "Select device for $purpose (or 'skip')" "skip")
      if [ "$choice" = "skip" ]; then
        return 1
      fi
    else
      choice=$(prompt_input "Select device for $purpose" "")
      if [ -z "$choice" ]; then
        warn "Device cannot be empty"
        continue
      fi
    fi
    if [ ! -b "/dev/$choice" ]; then
      warn "Device /dev/$choice not found"
      continue
    fi
    eval "$var_name=/dev/$choice"
    ok "Selected /dev/$choice for $purpose"
    return 0
  done
}

# Build list of setup strategies available for a given device
get_strategies_for_device() {
  local device="$1"
  local mount_point="$2"
  local strategies=()

  # Check if device has an existing VG with free space
  local vg_with_free=""
  if command -v pvs >/dev/null 2>&1; then
    # Check partitions on this device for LVM PVs
    while IFS= read -r pv_line; do
      local pv_name pv_vg pv_free
      pv_name=$(echo "$pv_line" | awk '{print $1}')
      pv_vg=$(echo "$pv_line" | awk '{print $2}')
      pv_free=$(echo "$pv_line" | awk '{print $6}')
      # Check if this PV belongs to our device (direct or via mapper/crypt)
      if lsblk -ln -o NAME "$device" 2>/dev/null | grep -q "$(basename "$pv_name" | sed 's|/dev/||')"; then
        local free_bytes
        free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$pv_vg" 2>/dev/null | tr -d ' ')
        if [ "${free_bytes:-0}" -gt 1073741824 ]; then  # > 1GB free
          vg_with_free="$pv_vg"
        fi
      fi
    done < <(pvs --noheadings 2>/dev/null)
  fi

  # Also check if root's VG has free space (common Ubuntu case)
  if [ -z "$vg_with_free" ]; then
    local root_vg
    root_vg=$(lvs --noheadings -o vg_name "$(findmnt -n -o SOURCE /)" 2>/dev/null | tr -d ' ')
    if [ -n "$root_vg" ]; then
      local free_bytes
      free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$root_vg" 2>/dev/null | tr -d ' ')
      if [ "${free_bytes:-0}" -gt 1073741824 ]; then
        # Only offer if the VG's PV lives on this device
        local vg_pv
        vg_pv=$(pvs --noheadings -o pv_name -S "vg_name=$root_vg" 2>/dev/null | tr -d ' ')
        if lsblk -ln -o PATH "$device" 2>/dev/null | grep -qF "$(echo "$vg_pv" | head -1)" || \
           lsblk -s -ln -o NAME "$device" 2>/dev/null | grep -q "$(basename "$vg_pv" | head -c 10)"; then
          vg_with_free="$root_vg"
        fi
      fi
    fi
  fi

  if [ -n "$vg_with_free" ]; then
    local vg_free_h
    vg_free_h=$(vgs --noheadings -o vg_free "$vg_with_free" 2>/dev/null | tr -d ' ')
    strategies+=("lvm — Create new logical volume in $vg_with_free (${vg_free_h} free)")
  fi

  # Check for existing partitions that could be reformatted
  local has_unmounted_parts=false
  while IFS= read -r part_line; do
    local part_name part_mount part_size part_fstype
    part_name=$(echo "$part_line" | awk '{print $1}')
    part_size=$(echo "$part_line" | awk '{print $2}')
    part_fstype=$(echo "$part_line" | awk '{print $4}')
    part_mount=$(echo "$part_line" | awk '{print $5}')
    if [ -z "$part_mount" ] && [ "$part_fstype" != "crypto_LUKS" ] && [ "$part_fstype" != "LVM2_member" ]; then
      has_unmounted_parts=true
      strategies+=("reformat:/dev/$part_name — Reformat /dev/$part_name ($part_size, $part_fstype) as ext4")
    fi
  done < <(lsblk -ln -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$device" 2>/dev/null | awk '$3 == "part"')

  # Check for free space on disk for new partition
  local free_space
  free_space=$(parted -s "$device" unit GB print free 2>/dev/null | awk '/Free Space/ {size=$3} END {print size}')
  if [ -n "$free_space" ] && [ "$free_space" != "0.00GB" ]; then
    strategies+=("partition — Create new partition in free space (${free_space} available)")
  fi

  # Always offer these
  strategies+=("directory — Use subdirectory on current filesystem (no disk changes)")
  strategies+=("erase — Wipe entire disk and use LVM (DESTROYS ALL DATA)")
  strategies+=("skip — Don't set up $mount_point")

  printf '%s\n' "${strategies[@]}"
}

setup_disk_and_mount() {
  local device="$1"
  local mount_point="$2"

  if mountpoint -q "$mount_point"; then
    ok "$mount_point already mounted, skipping"
    return
  fi

  # Show current state
  warn "Current state of $device:"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$device" 2>/dev/null || true
  echo ""

  # Build and present strategies
  local strategies=()
  while IFS= read -r s; do
    strategies+=("$s")
  done < <(get_strategies_for_device "$device" "$mount_point")

  local strategy
  strategy=$(prompt_choose "How do you want to set up $mount_point?" "${strategies[@]}")

  case "$strategy" in
    lvm*)       setup_lvm_volume_and_mount "$device" "$mount_point" ;;
    reformat:*) setup_reformat_and_mount "$strategy" "$mount_point" ;;
    partition*) setup_partition_and_mount "$device" "$mount_point" ;;
    directory*) setup_directory "$mount_point" ;;
    erase*)     setup_erase_lvm_and_mount "$device" "$mount_point" ;;
    skip*)      warn "Skipped $mount_point setup"; return 0 ;;
  esac
}

# Create a new LV in an existing VG with free space
setup_lvm_volume_and_mount() {
  local device="$1"
  local mount_point="$2"

  # Find the VG with free space
  local vg_name=""
  local root_vg
  root_vg=$(lvs --noheadings -o vg_name "$(findmnt -n -o SOURCE /)" 2>/dev/null | tr -d ' ')
  if [ -n "$root_vg" ]; then
    local free_bytes
    free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$root_vg" 2>/dev/null | tr -d ' ')
    if [ "${free_bytes:-0}" -gt 1073741824 ]; then
      vg_name="$root_vg"
    fi
  fi

  if [ -z "$vg_name" ]; then
    error "No volume group with free space found"
    return 1
  fi

  local vg_free_h
  vg_free_h=$(vgs --noheadings -o vg_free "$vg_name" 2>/dev/null | tr -d ' ')
  local lv_name
  lv_name=$(basename "$mount_point" | tr -cd 'a-zA-Z0-9')

  info "Volume group $vg_name has $vg_free_h free"

  local lv_size
  lv_size=$(prompt_input "Size for new logical volume (e.g. 200G, or '80%FREE' for 80% of free space)" "80%FREE")

  if ! prompt_yes_no "Create ${lv_size} logical volume '$lv_name' in $vg_name?"; then
    warn "LVM setup aborted"
    return 1
  fi

  if [[ "$lv_size" == *%* ]]; then
    lvcreate -l "$lv_size" -n "$lv_name" "$vg_name"
  else
    lvcreate -L "$lv_size" -n "$lv_name" "$vg_name"
  fi

  local lv_path="/dev/$vg_name/$lv_name"
  info "Formatting $lv_path as ext4..."
  mkfs.ext4 -q "$lv_path"

  mkdir -p "$mount_point"

  if ! grep -qF "$mount_point" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak
    echo "$lv_path $mount_point ext4 defaults 0 2" >> /etc/fstab
  fi

  mount "$mount_point"
  ok "$mount_point ready on $lv_path"
}

# Reformat an existing unmounted partition
setup_reformat_and_mount() {
  local strategy="$1"
  local mount_point="$2"

  # Extract partition path from strategy string "reformat:/dev/sda1 — ..."
  local partition
  partition=$(echo "$strategy" | sed 's/reformat:\(\/dev\/[^ ]*\).*/\1/')

  local part_size part_fstype
  part_size=$(lsblk -dn -o SIZE "$partition" 2>/dev/null)
  part_fstype=$(lsblk -dn -o FSTYPE "$partition" 2>/dev/null)

  warn "$partition is currently ${part_fstype} (${part_size})"

  if ! prompt_yes_no "Reformat $partition as ext4? This will ERASE all data on this partition." "n"; then
    warn "Reformat aborted"
    return 1
  fi

  info "Formatting $partition as ext4..."
  mkfs.ext4 -q "$partition"

  mkdir -p "$mount_point"

  local fstab_id
  fstab_id=$(blkid -s UUID -o value "$partition")
  if ! grep -qF "$mount_point" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak
    echo "UUID=$fstab_id $mount_point ext4 defaults 0 2" >> /etc/fstab
  fi

  mount "$mount_point"
  ok "$mount_point ready on $partition"
}

# Create a new partition in free disk space
setup_partition_and_mount() {
  local device="$1"
  local mount_point="$2"

  info "Creating new partition on $device for $mount_point..."

  local free_space
  free_space=$(parted -s "$device" unit GB print free 2>/dev/null | awk '/Free Space/ {size=$3} END {print size}')
  info "Available free space: ${free_space:-unknown}"

  if ! prompt_yes_no "Create new partition using free space on $device?"; then
    warn "Partition creation aborted"
    return 1
  fi

  # Find the start of the last free space block
  local free_start free_end
  read -r free_start free_end < <(parted -s "$device" unit s print free 2>/dev/null \
    | awk '/Free Space/ {start=$1; end=$2} END {print start, end}')

  parted -s -a optimal "$device" mkpart primary ext4 "$free_start" "$free_end" || {
    error "Failed to create partition. You may need to do this manually."
    return 1
  }

  sleep 1
  partprobe "$device" 2>/dev/null || true

  # Find the newly created partition
  local new_part
  new_part=$(lsblk -ln -o PATH "$device" 2>/dev/null | tail -1)

  if [ -z "$new_part" ] || [ ! -b "$new_part" ]; then
    error "Could not detect new partition"
    return 1
  fi

  info "Formatting $new_part as ext4..."
  mkfs.ext4 -q "$new_part"

  mkdir -p "$mount_point"

  local fstab_id
  fstab_id=$(blkid -s UUID -o value "$new_part")
  if ! grep -qF "$mount_point" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak
    echo "UUID=$fstab_id $mount_point ext4 defaults 0 2" >> /etc/fstab
  fi

  mount "$mount_point"
  ok "$mount_point ready on $new_part"
}

# Use a subdirectory on the existing filesystem
setup_directory() {
  local mount_point="$1"

  info "Using $mount_point as a regular directory (no separate mount)"
  mkdir -p "$mount_point"
  ok "$mount_point ready (subdirectory on root filesystem)"
}

# Wipe entire disk and set up fresh LVM
setup_erase_lvm_and_mount() {
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

  # Extra confirmation for safety
  if ! prompt_yes_no "Are you SURE? All partitions on $device will be destroyed." "n"; then
    warn "Disk setup aborted for $device"
    return 1
  fi

  wipefs -a "$device"

  if ! pvcreate -f "$device"; then
    error "pvcreate failed on $device"
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

  info "You'll now configure storage for apps/databases and media."
  info "You can use the same disk for both, or different disks."
  echo ""

  if select_disk "/data (apps + databases)" DATA_DEVICE; then
    setup_disk_and_mount "$DATA_DEVICE" "$DATA_DIR"
    mkdir -p "$DATA_DIR"/{databases,config,apps} 2>/dev/null || true
  fi

  echo ""
  if select_disk "/storage (media + photos)" STORAGE_DEVICE "skip"; then
    setup_disk_and_mount "$STORAGE_DEVICE" "$STORAGE_DIR"
    mkdir -p "$STORAGE_DIR"/{media,torrents,photos,backups} 2>/dev/null || true
  fi

  chown -R "$(get_user):$(get_user)" "$DATA_DIR" 2>/dev/null || true
  chown -R "$(get_user):$(get_user)" "$STORAGE_DIR" 2>/dev/null || true
}
