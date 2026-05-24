#!/bin/bash
set -euo pipefail

# homekase-backup — Docker-label-driven backup engine
# Reads backup configuration from Docker container labels:
#   homekase.backup.type=snapshot|incremental
#   homekase.backup.source=/path/to/data
#   homekase.backup.retention=7           (snapshot only: keep N copies)
#   homekase.backup.command=pg_dump ...   (snapshot only: custom dump command)
#   homekase.backup.name=myapp-db         (optional: override backup folder name)

BACKUP_DIR="${BACKUP_DIR:-/backups}"
SNAPSHOT_DIR="$BACKUP_DIR/snapshots"
INCREMENTAL_DIR="$BACKUP_DIR/incremental"
LOG_FILE="$BACKUP_DIR/backup.log"
DATE_TAG=$(date +%Y%m%d-%H%M%S)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Get all containers with homekase.backup.type label
get_backup_containers() {
  docker ps --filter "label=homekase.backup.type" --format '{{.Names}}' 2>/dev/null
}

# Read a label from a container
get_label() {
  local container="$1"
  local label="$2"
  local default="${3:-}"
  local value
  value=$(docker inspect --format "{{index .Config.Labels \"$label\"}}" "$container" 2>/dev/null || echo "")
  if [ -z "$value" ] || [ "$value" = "<no value>" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

run_snapshot_backup() {
  local container="$1"
  local source command retention backup_name backup_path

  backup_name=$(get_label "$container" "homekase.backup.name" "$container")
  source=$(get_label "$container" "homekase.backup.source" "")
  command=$(get_label "$container" "homekase.backup.command" "")
  retention=$(get_label "$container" "homekase.backup.retention" "7")

  backup_path="$SNAPSHOT_DIR/$backup_name"
  mkdir -p "$backup_path"

  local snapshot_file="$backup_path/${backup_name}-${DATE_TAG}.tar.gz"

  if [ -n "$command" ]; then
    # Custom command (e.g. pg_dump) — run inside container, compress output
    log "[$backup_name] Running snapshot command: $command"
    local dump_file="$backup_path/${backup_name}-${DATE_TAG}.sql.gz"
    docker exec "$container" sh -c "$command" | gzip > "$dump_file" 2>> "$LOG_FILE"
    if [ $? -eq 0 ] && [ -s "$dump_file" ]; then
      log "[$backup_name] Snapshot saved: $dump_file"
    else
      log "[$backup_name] ERROR: Snapshot command failed"
      rm -f "$dump_file"
      return 1
    fi
  elif [ -n "$source" ]; then
    # Directory snapshot — tar + gzip
    log "[$backup_name] Snapshotting $source"
    if [ -d "$source" ]; then
      tar czf "$snapshot_file" -C "$(dirname "$source")" "$(basename "$source")" 2>> "$LOG_FILE"
      log "[$backup_name] Snapshot saved: $snapshot_file"
    else
      log "[$backup_name] ERROR: Source directory $source not found"
      return 1
    fi
  else
    log "[$backup_name] ERROR: No source or command defined"
    return 1
  fi

  # Enforce retention — delete oldest snapshots beyond limit
  local count
  count=$(find "$backup_path" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.sql.gz" \) | wc -l)
  if [ "$count" -gt "$retention" ]; then
    local to_delete=$((count - retention))
    log "[$backup_name] Enforcing retention ($retention): removing $to_delete old snapshot(s)"
    find "$backup_path" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.sql.gz" \) -printf '%T+ %p\n' \
      | sort | head -n "$to_delete" | awk '{print $2}' | xargs rm -f
  fi
}

run_incremental_backup() {
  local container="$1"
  local source backup_name backup_path

  backup_name=$(get_label "$container" "homekase.backup.name" "$container")
  source=$(get_label "$container" "homekase.backup.source" "")

  if [ -z "$source" ]; then
    log "[$backup_name] ERROR: No source defined for incremental backup"
    return 1
  fi

  if [ ! -d "$source" ]; then
    log "[$backup_name] ERROR: Source directory $source not found"
    return 1
  fi

  backup_path="$INCREMENTAL_DIR/$backup_name"
  mkdir -p "$backup_path"

  log "[$backup_name] Incremental backup: $source -> $backup_path"
  rsync -a --delete --info=stats2 "$source/" "$backup_path/" 2>> "$LOG_FILE"
  log "[$backup_name] Incremental backup complete"
}

run_all_backups() {
  log "=== Backup run started ==="

  local containers
  containers=$(get_backup_containers)

  if [ -z "$containers" ]; then
    log "No containers with homekase.backup labels found"
    return 0
  fi

  local success=0
  local failed=0

  while IFS= read -r container; do
    local backup_type
    backup_type=$(get_label "$container" "homekase.backup.type" "")

    case "$backup_type" in
      snapshot)
        if run_snapshot_backup "$container"; then
          ((++success))
        else
          ((++failed))
        fi
        ;;
      incremental)
        if run_incremental_backup "$container"; then
          ((++success))
        else
          ((++failed))
        fi
        ;;
      *)
        log "[$container] Unknown backup type: $backup_type"
        ((++failed))
        ;;
    esac
  done <<< "$containers"

  log "=== Backup run complete: $success succeeded, $failed failed ==="
}

show_status() {
  echo "Backup Status"
  echo "============="
  echo ""

  echo "Containers with backup labels:"
  local containers
  containers=$(get_backup_containers)
  if [ -z "$containers" ]; then
    echo "  (none found)"
    return
  fi

  while IFS= read -r container; do
    local backup_type source retention backup_name command
    backup_type=$(get_label "$container" "homekase.backup.type" "")
    backup_name=$(get_label "$container" "homekase.backup.name" "$container")
    source=$(get_label "$container" "homekase.backup.source" "")
    retention=$(get_label "$container" "homekase.backup.retention" "7")
    command=$(get_label "$container" "homekase.backup.command" "")

    echo "  $backup_name ($container)"
    echo "    type:      $backup_type"
    [ -n "$source" ] && echo "    source:    $source"
    [ -n "$command" ] && echo "    command:   $command"
    [ "$backup_type" = "snapshot" ] && echo "    retention: $retention"

    # Show existing backups
    local backup_path
    if [ "$backup_type" = "snapshot" ]; then
      backup_path="$SNAPSHOT_DIR/$backup_name"
    else
      backup_path="$INCREMENTAL_DIR/$backup_name"
    fi
    if [ -d "$backup_path" ]; then
      local count
      count=$(find "$backup_path" -maxdepth 1 -type f 2>/dev/null | wc -l)
      local size
      size=$(du -sh "$backup_path" 2>/dev/null | awk '{print $1}')
      echo "    backups:   $count files, $size total"
    else
      echo "    backups:   (none yet)"
    fi
    echo ""
  done <<< "$containers"
}

case "${1:-run}" in
  run)    run_all_backups ;;
  status) show_status ;;
  *)
    echo "Usage: homekase-backup [run|status]"
    echo "  run    — Execute all backups (default)"
    echo "  status — Show backup configuration and status"
    exit 1
    ;;
esac
