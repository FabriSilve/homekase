#!/bin/bash

# Partitions that must never be reformatted or erased
is_protected_partition() {
  local part_path="$1"
  local mount fstype

  mount=$(lsblk -dn -o MOUNTPOINT "$part_path" 2>/dev/null)
  fstype=$(lsblk -dn -o FSTYPE "$part_path" 2>/dev/null)

  # Protected if mounted to critical paths
  case "$mount" in
    /|/boot|/boot/efi) return 0 ;;
  esac

  # Protected if LUKS or LVM PV (part of OS chain)
  case "$fstype" in
    crypto_LUKS|LVM2_member) return 0 ;;
  esac

  return 1
}

# Check if a whole disk contains protected partitions (unsafe to erase)
disk_has_protected_partitions() {
  local device="$1"
  while IFS= read -r part_path; do
    [ -b "$part_path" ] || continue
    if is_protected_partition "$part_path"; then
      return 0
    fi
  done < <(lsblk -ln -o PATH "$device" 2>/dev/null | tail -n +2)
  return 1
}

show_disk_overview() {
  header "Disk Overview"

  local os_device
  os_device=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | xargs basename)

  # Explanation of what we're doing
  section "Storage Configuration" \
    "homekase uses three storage areas:
  /data     — Apps, databases, Docker configs (fast storage, SSD preferred)
  /storage  — Media files, photos, torrents (large capacity, HDD is fine)
  /backups  — Automated snapshots and incremental backups (separate disk ideal)

You can put them on the same disk or use separate disks.
Ideally, backups live on a different disk than the data they protect."

  # Show each disk with its partitions
  echo -e "${BOLD}Your disks and partitions:${NC}"
  echo ""

  for dev in /dev/sd? /dev/nvme?n?; do
    [ -b "$dev" ] || continue
    local name size model
    name=$(basename "$dev")
    size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null)
    model=$(lsblk -dn -o MODEL "$dev" 2>/dev/null | xargs)

    local disk_label=""
    if [ "$name" = "$os_device" ]; then
      disk_label=" ${YELLOW}(OS disk)${NC}"
    fi

    echo -e "  ${BOLD}$name${NC} — ${size}, ${model}${disk_label}"

    # Show partitions
    while IFS= read -r line; do
      local p_name p_size p_type p_fstype p_mount
      p_name=$(echo "$line" | awk '{print $1}')
      p_size=$(echo "$line" | awk '{print $2}')
      p_type=$(echo "$line" | awk '{print $3}')
      p_fstype=$(echo "$line" | awk '{print $4}')
      p_mount=$(echo "$line" | awk '{$1=$2=$3=$4=""; print}' | xargs)

      [ "$p_type" = "disk" ] && continue

      local status=""
      local part_path="/dev/$p_name"
      # Also check mapper devices (LVM LVs shown under the disk tree)
      if [ ! -b "$part_path" ]; then
        part_path="/dev/mapper/$p_name"
      fi

      if [ -b "$part_path" ] && is_protected_partition "$part_path"; then
        status="${RED}[protected]${NC}"
      elif [ -n "$p_mount" ]; then
        status="${YELLOW}[mounted]${NC}"
      elif [ -n "$p_fstype" ] && [ "$p_fstype" != " " ]; then
        status="${GREEN}[available]${NC}"
      fi

      local mount_info=""
      if [ -n "$p_mount" ]; then
        mount_info=" -> $p_mount"
      fi

      # Indent based on depth (partitions vs LVM/crypt children)
      local indent="    "
      if [ "$p_type" = "lvm" ] || [ "$p_type" = "crypt" ]; then
        indent="      "
      fi

      echo -e "${indent}${p_name} ${p_size} ${p_fstype:-—} ${mount_info} ${status}"
    done < <(lsblk -ln -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$dev" 2>/dev/null)

    echo ""
  done

  # Show LVM free space prominently
  if command -v vgs >/dev/null 2>&1; then
    while IFS= read -r line; do
      local vg_name vg_free
      vg_name=$(echo "$line" | awk '{print $1}')
      vg_free=$(echo "$line" | awk '{print $7}')
      local free_bytes
      free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$vg_name" 2>/dev/null | tr -d ' ')
      if [ "${free_bytes:-0}" -gt 1073741824 ]; then
        echo -e "  ${GREEN}${BOLD}LVM free space:${NC} ${vg_free} available in volume group ${BOLD}${vg_name}${NC}"
        echo -e "  ${CYAN}(New logical volumes can be created here without repartitioning)${NC}"
        echo ""
      fi
    done < <(vgs --noheadings 2>/dev/null)
  fi

  echo -e "  ${RED}[protected]${NC} = OS/boot/encryption — cannot be modified"
  echo -e "  ${YELLOW}[mounted]${NC}   = currently in use"
  echo -e "  ${GREEN}[available]${NC} = unmounted, can be reformatted"
  echo ""
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
    while IFS= read -r pv_line; do
      local pv_name pv_vg
      pv_name=$(echo "$pv_line" | awk '{print $1}')
      pv_vg=$(echo "$pv_line" | awk '{print $2}')
      if lsblk -ln -o NAME "$device" 2>/dev/null | grep -q "$(basename "$pv_name" | sed 's|/dev/||')"; then
        local free_bytes
        free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$pv_vg" 2>/dev/null | tr -d ' ')
        if [ "${free_bytes:-0}" -gt 1073741824 ]; then
          vg_with_free="$pv_vg"
        fi
      fi
    done < <(pvs --noheadings 2>/dev/null)
  fi

  # Also check root's VG (common Ubuntu case: LVM inside LUKS)
  if [ -z "$vg_with_free" ]; then
    local root_vg
    root_vg=$(lvs --noheadings -o vg_name "$(findmnt -n -o SOURCE /)" 2>/dev/null | tr -d ' ')
    if [ -n "$root_vg" ]; then
      local free_bytes
      free_bytes=$(vgs --noheadings --nosuffix --units b -o vg_free "$root_vg" 2>/dev/null | tr -d ' ')
      if [ "${free_bytes:-0}" -gt 1073741824 ]; then
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
    strategies+=("lvm — New logical volume in $vg_with_free (${vg_free_h} free, no repartitioning needed)")
  fi

  # Check for existing unmounted, unprotected partitions
  while IFS= read -r part_line; do
    local part_name part_size part_fstype part_mount
    part_name=$(echo "$part_line" | awk '{print $1}')
    part_size=$(echo "$part_line" | awk '{print $2}')
    part_fstype=$(echo "$part_line" | awk '{print $4}')
    part_mount=$(echo "$part_line" | awk '{print $5}')

    # Skip protected partitions
    if is_protected_partition "/dev/$part_name"; then
      continue
    fi
    # Skip mounted partitions
    if [ -n "$part_mount" ]; then
      continue
    fi

    local fs_label="${part_fstype:-unformatted}"
    strategies+=("reformat:/dev/$part_name — Reformat /dev/$part_name ($part_size, $fs_label) as ext4")
  done < <(lsblk -ln -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$device" 2>/dev/null | awk '$3 == "part"')

  # Check for free space on disk for new partition
  local free_space
  free_space=$(parted -s "$device" unit GB print free 2>/dev/null | awk '/Free Space/ {size=$3} END {print size}')
  if [ -n "$free_space" ] && [ "$free_space" != "0.00GB" ]; then
    strategies+=("partition — Create new partition in free space (${free_space} available)")
  fi

  # Subdirectory is always safe
  strategies+=("directory — Use subdirectory on current root filesystem (no disk changes)")

  # Only offer full-disk erase if no protected partitions on this disk
  if ! disk_has_protected_partitions "$device"; then
    strategies+=("erase — Wipe entire disk and use LVM (DESTROYS ALL DATA)")
  fi

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

  # Build and present strategies
  local strategies=()
  while IFS= read -r s; do
    strategies+=("$s")
  done < <(get_strategies_for_device "$device" "$mount_point")

  local strategy
  strategy=$(prompt_choose "How do you want to set up $mount_point on $device?" "${strategies[@]}")

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
  info "Your OS uses a separate logical volume — this won't affect it."

  local lv_size
  lv_size=$(prompt_input "Size for new logical volume (e.g. 200G, or '80%FREE' for 80% of free space)" "80%FREE")

  if ! prompt_yes_no "Create ${lv_size} logical volume '$lv_name' in $vg_name, formatted as ext4?"; then
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

  local partition
  partition=$(echo "$strategy" | sed 's/reformat:\(\/dev\/[^ ]*\).*/\1/')

  # Double-check protection (belt and suspenders)
  if is_protected_partition "$partition"; then
    error "Cannot reformat $partition — it is a protected system partition"
    return 1
  fi

  local part_size part_fstype
  part_size=$(lsblk -dn -o SIZE "$partition" 2>/dev/null)
  part_fstype=$(lsblk -dn -o FSTYPE "$partition" 2>/dev/null)

  warn "$partition is currently ${part_fstype:-unformatted} (${part_size})"

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

  if ! prompt_yes_no "Create new ext4 partition using free space on $device?"; then
    warn "Partition creation aborted"
    return 1
  fi

  local free_start free_end
  read -r free_start free_end < <(parted -s "$device" unit s print free 2>/dev/null \
    | awk '/Free Space/ {start=$1; end=$2} END {print start, end}')

  parted -s -a optimal "$device" mkpart primary ext4 "$free_start" "$free_end" || {
    error "Failed to create partition. You may need to do this manually."
    return 1
  }

  sleep 1
  partprobe "$device" 2>/dev/null || true

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

  info "Using $mount_point as a regular directory on the root filesystem"
  mkdir -p "$mount_point"
  ok "$mount_point ready (subdirectory, no separate mount)"
}

# Wipe entire disk and set up fresh LVM
setup_erase_lvm_and_mount() {
  local device="$1"
  local mount_point="$2"

  # Final safety check
  if disk_has_protected_partitions "$device"; then
    error "Cannot erase $device — it contains protected system partitions"
    return 1
  fi

  local vg_name
  vg_name=$(basename "$device")-vg

  info "Setting up LVM on $device for $mount_point..."
  info "LVM will use 80% of disk space, leaving 20% unallocated for future expansion."

  if ! prompt_yes_no "This will ERASE ALL DATA on $device. Continue?" "n"; then
    warn "Disk setup aborted for $device"
    return 1
  fi

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
  show_disk_overview

  if select_disk "/data (apps + databases)" DATA_DEVICE; then
    setup_disk_and_mount "$DATA_DEVICE" "$DATA_DIR"
    mkdir -p "$DATA_DIR"/{databases,config,apps} 2>/dev/null || true
  fi

  echo ""
  if select_disk "/storage (media + photos)" STORAGE_DEVICE "skip"; then
    setup_disk_and_mount "$STORAGE_DEVICE" "$STORAGE_DIR"
    mkdir -p "$STORAGE_DIR"/{media,torrents,photos} 2>/dev/null || true
  fi

  echo ""
  if select_disk "/backups (automated snapshots + incremental backups)" BACKUP_DEVICE "skip"; then
    setup_disk_and_mount "$BACKUP_DEVICE" "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"/{snapshots,incremental} 2>/dev/null || true
  fi

  chown -R "$(get_user):$(get_user)" "$DATA_DIR" 2>/dev/null || true
  chown -R "$(get_user):$(get_user)" "$STORAGE_DIR" 2>/dev/null || true
  chown -R "$(get_user):$(get_user)" "$BACKUP_DIR" 2>/dev/null || true
}
