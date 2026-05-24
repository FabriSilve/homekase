#!/bin/bash

deploy_backup_service() {
  header "Backup Service"

  if [ ! -d "$BACKUP_DIR" ]; then
    warn "No backup directory configured — skipping backup setup"
    info "Re-run setup and configure /backups in the disk setup step"
    return
  fi

  section "Automated Backups" \
    "Backups are driven by Docker labels on your services — like Traefik routes.
Two backup types:
  snapshot    — Periodic full dumps (databases, configs). Keeps N copies.
  incremental — rsync-based sync (photos, documents). Always up-to-date.

Labels are added to each service's docker-compose.yml.
A daily cron job reads labels and runs the appropriate backup."

  if ! prompt_yes_no "Enable automated backups?"; then
    warn "Backup service skipped"
    return
  fi

  # Install backup script
  install_backup_script

  # Configure backup schedule
  local schedule
  schedule=$(prompt_choose "How often should backups run?" \
    "daily — Once per day at 3:00 AM (recommended)" \
    "twice — Twice per day at 3:00 AM and 3:00 PM" \
    "hourly — Every hour")

  local cron_schedule
  case "$schedule" in
    daily*)  cron_schedule="0 3 * * *" ;;
    twice*)  cron_schedule="0 3,15 * * *" ;;
    hourly*) cron_schedule="0 * * * *" ;;
  esac

  install_backup_cron "$cron_schedule"

  # Offer to add backup labels to deployed services
  add_backup_labels_to_services

  ok "Backup service configured"
  info "Run 'homekase-backup status' to view backup configuration"
  info "Run 'homekase-backup run' to trigger a manual backup"
}

install_backup_script() {
  cp "$SCRIPT_DIR/scripts/homekase-backup.sh" /usr/local/bin/homekase-backup
  chmod +x /usr/local/bin/homekase-backup
  ok "Backup script installed to /usr/local/bin/homekase-backup"
}

install_backup_cron() {
  local cron_schedule="$1"
  local cron_line="$cron_schedule root BACKUP_DIR=$BACKUP_DIR /usr/local/bin/homekase-backup run"
  local cron_file="/etc/cron.d/homekase-backup"

  cat > "$cron_file" << CRON
# homekase automated backups
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
$cron_line
CRON

  chmod 644 "$cron_file"
  ok "Backup cron installed ($cron_schedule)"
}

add_backup_labels_to_services() {
  info "Checking deployed services for backup label configuration..."
  echo ""

  # Immich DB — snapshot with pg_dump
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^immich-db$"; then
    if prompt_yes_no "Add snapshot backup for Immich database?"; then
      local retention
      retention=$(prompt_input "How many snapshots to keep?" "7")
      add_labels_to_compose "immich" "immich-db" \
        "homekase.backup.type=snapshot" \
        "homekase.backup.name=immich-db" \
        "homekase.backup.command=pg_dump -U postgres immich" \
        "homekase.backup.retention=$retention"
      ok "Immich DB backup labels added (retention: $retention)"
    fi
  fi

  # Immich photos — incremental with hardlinks
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^immich-server$"; then
    local photos_path="${STORAGE_DIR:-$DATA_DIR}/photos"
    if prompt_yes_no "Add incremental backup for photos ($photos_path)?"; then
      local retention
      retention=$(prompt_input "How many daily versions to keep?" "7")
      add_labels_to_compose "immich" "immich-server" \
        "homekase.backup.type=incremental" \
        "homekase.backup.name=photos" \
        "homekase.backup.source=$photos_path" \
        "homekase.backup.retention=$retention"
      ok "Photos incremental backup labels added (retention: $retention versions)"
    fi
  fi

  # AdGuard config — snapshot
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^adguard$"; then
    if prompt_yes_no "Add snapshot backup for AdGuard config?"; then
      local retention
      retention=$(prompt_input "How many snapshots to keep?" "7")
      add_labels_to_compose "traefik" "adguard" \
        "homekase.backup.type=snapshot" \
        "homekase.backup.name=adguard-config" \
        "homekase.backup.source=$DATA_DIR/config/adguard" \
        "homekase.backup.retention=$retention"
      ok "AdGuard config backup labels added"
    fi
  fi

  # Jellyfin config — snapshot
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^jellyfin$"; then
    if prompt_yes_no "Add snapshot backup for Jellyfin config?"; then
      local retention
      retention=$(prompt_input "How many snapshots to keep?" "7")
      add_labels_to_compose "jellyfin" "jellyfin" \
        "homekase.backup.type=snapshot" \
        "homekase.backup.name=jellyfin-config" \
        "homekase.backup.source=$DATA_DIR/config/jellyfin" \
        "homekase.backup.retention=$retention"
      ok "Jellyfin config backup labels added"
    fi
  fi

  # Syncthing config — snapshot
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^syncthing$"; then
    if prompt_yes_no "Add snapshot backup for Syncthing config?"; then
      local retention
      retention=$(prompt_input "How many snapshots to keep?" "7")
      add_labels_to_compose "syncthing" "syncthing" \
        "homekase.backup.type=snapshot" \
        "homekase.backup.name=syncthing-config" \
        "homekase.backup.source=$DATA_DIR/config/syncthing" \
        "homekase.backup.retention=$retention"
      ok "Syncthing config backup labels added"
    fi
  fi

  # Beszel config — snapshot
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^beszel$"; then
    if prompt_yes_no "Add snapshot backup for Beszel config?"; then
      local retention
      retention=$(prompt_input "How many snapshots to keep?" "7")
      add_labels_to_compose "monitoring" "beszel-hub" \
        "homekase.backup.type=snapshot" \
        "homekase.backup.name=beszel-config" \
        "homekase.backup.source=$DATA_DIR/config/beszel" \
        "homekase.backup.retention=$retention"
      ok "Beszel config backup labels added"
    fi
  fi
}

# Add labels to an existing docker-compose.yml service and redeploy
add_labels_to_compose() {
  local project="$1"
  local service="$2"
  shift 2
  local labels=("$@")

  # Find the compose file
  local compose_file=""
  for candidate in \
    "$HOMELAB_DIR/$project/docker-compose.yml" \
    "$HOMELAB_DIR/$project/$project.yml" \
    "$HOMELAB_DIR/traefik/$project.yml" \
    "$HOMELAB_DIR/traefik/adguard.yml"; do
    if [ -f "$candidate" ] && grep -q "$service" "$candidate" 2>/dev/null; then
      compose_file="$candidate"
      break
    fi
  done

  if [ -z "$compose_file" ]; then
    warn "Could not find compose file for $project/$service"
    return 1
  fi

  # Check if labels section exists for this service
  # Add backup labels under the existing labels block
  for label in "${labels[@]}"; do
    if grep -qF "\"$label\"" "$compose_file" 2>/dev/null; then
      continue  # Label already present
    fi
    # Find the labels section for the service and append
    # Use sed to add after the last traefik label or after "labels:" for the service
    if grep -q "traefik\." "$compose_file" && grep -A 50 "$service:" "$compose_file" | grep -q "traefik\."; then
      # Add after last traefik label in the service block
      local last_traefik_line
      last_traefik_line=$(grep -n "traefik\." "$compose_file" | tail -1 | cut -d: -f1)
      sed -i "${last_traefik_line}a\\      - \"${label}\"" "$compose_file"
    elif grep -A 50 "$service:" "$compose_file" | grep -q "labels:"; then
      # Add after labels: line
      local labels_line
      labels_line=$(awk "/$service:/,/labels:/" "$compose_file" | grep -c "" | head -1)
      local service_line
      service_line=$(grep -n "$service:" "$compose_file" | head -1 | cut -d: -f1)
      local actual_labels_line=$((service_line + labels_line - 1))
      sed -i "${actual_labels_line}a\\      - \"${label}\"" "$compose_file"
    else
      # No labels section — add one after the service container_name or image line
      local anchor_line
      anchor_line=$(grep -n -m1 "container_name.*$service\|image:" "$compose_file" | tail -1 | cut -d: -f1)
      if [ -n "$anchor_line" ]; then
        sed -i "${anchor_line}a\\    labels:\\n      - \"${label}\"" "$compose_file"
      else
        warn "Could not find insertion point for labels in $compose_file"
        return 1
      fi
    fi
  done

  # Redeploy to pick up new labels
  info "Redeploying $project to apply backup labels..."
  docker compose -f "$compose_file" up -d 2>/dev/null || true
}
