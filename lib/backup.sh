#!/usr/bin/env bash
# homekase backup [app-name] [--incremental]
# Snapshots app data + databases. Cron-safe (exits 0 if nothing to do).
# Lock at /tmp/homekase-backup.lock prevents overlapping runs.

BACKUP_LOCK="/tmp/homekase-backup.lock"
BACKUP_LOG=""   # set after config is loaded

_backup_acquire_lock() {
  if [[ -e "${BACKUP_LOCK}" ]]; then
    local pid
    pid="$(cat "${BACKUP_LOCK}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      error "Another homekase backup is already running (PID ${pid}). Exiting."
      exit 1
    fi
    rm -f "${BACKUP_LOCK}"
  fi
  echo "$$" > "${BACKUP_LOCK}"
}

_backup_release_lock() {
  rm -f "${BACKUP_LOCK}"
}

_backup_log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[${ts}] $*" >> "${BACKUP_LOG}"
}

_backup_get_label() {
  local cname="$1" label="$2"
  docker inspect "${cname}" --format "{{index .Config.Labels \"${label}\"}}" 2>/dev/null || true
}

_backup_get_env() {
  local cname="$1" varname="$2"
  docker inspect "${cname}" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep "^${varname}=" \
    | head -1 \
    | cut -d= -f2- \
    || true
}

_backup_dump_db() {
  local cname="$1" db_type="$2" dest="$3"

  case "${db_type}" in
    postgres)
      local pg_user pg_db
      pg_user="$(_backup_get_env "${cname}" POSTGRES_USER)"
      pg_db="$(_backup_get_env "${cname}" POSTGRES_DB)"
      info "Dumping PostgreSQL database (${pg_db})..."
      docker exec "${cname}" pg_dump -U "${pg_user}" "${pg_db}" > "${dest}/db.sql"
      ok "pg_dump written to ${dest}/db.sql"
      ;;
    mysql)
      local mysql_user mysql_pass mysql_db
      mysql_user="$(_backup_get_env "${cname}" MYSQL_USER)"
      mysql_pass="$(_backup_get_env "${cname}" MYSQL_PASSWORD)"
      mysql_db="$(_backup_get_env "${cname}" MYSQL_DATABASE)"
      info "Dumping MySQL database (${mysql_db})..."
      docker exec "${cname}" mysqldump -u "${mysql_user}" -p"${mysql_pass}" "${mysql_db}" > "${dest}/db.sql"
      ok "mysqldump written to ${dest}/db.sql"
      ;;
    mongodb)
      info "Dumping MongoDB..."
      docker exec "${cname}" mongodump --out /tmp/mongodump
      docker cp "${cname}:/tmp/mongodump" "${dest}/mongodump"
      ok "mongodump written to ${dest}/mongodump/"
      ;;
    none|"")
      ;;
    *)
      warn "Unknown db-type '${db_type}' for container ${cname} — skipping DB dump"
      ;;
  esac
}

_backup_snapshot() {
  local app="$1" cname="$2"

  local backup_data backup_storage db_type
  backup_data="$(_backup_get_label "${cname}" "com.homekase.backup.data")"
  backup_storage="$(_backup_get_label "${cname}" "com.homekase.backup.storage")"
  db_type="$(_backup_get_label "${cname}" "com.homekase.backup.db-type")"

  local date_tag
  date_tag="$(date +%Y%m%d-%H%M%S)"
  local dest="${BACKUP_LOG%/backup.log}/${app}/${date_tag}"
  mkdir -p "${dest}"

  info "Backing up ${app} → ${dest}"

  _backup_dump_db "${cname}" "${db_type}" "${dest}"

  if [[ -n "${backup_data}" ]]; then
    info "Archiving data: ${backup_data}"
    tar -czf "${dest}/data.tar.gz" -C / "${backup_data#/}"
    ok "data.tar.gz written"
  fi

  if [[ -n "${backup_storage}" && "${backup_storage}" != "null" ]]; then
    info "Archiving storage: ${backup_storage}"
    tar -czf "${dest}/storage.tar.gz" -C / "${backup_storage#/}"
    ok "storage.tar.gz written"
  fi

  _backup_log "OK  ${app}  snapshot  ${dest}"
  ok "Backed up ${app} to ${dest}"
}

_backup_incremental() {
  local app="$1" cname="$2"

  local backup_data backup_storage db_type
  backup_data="$(_backup_get_label "${cname}" "com.homekase.backup.data")"
  backup_storage="$(_backup_get_label "${cname}" "com.homekase.backup.storage")"
  db_type="$(_backup_get_label "${cname}" "com.homekase.backup.db-type")"

  local app_backup_dir="${BACKUP_LOG%/backup.log}/${app}"
  local date_tag
  date_tag="$(date +%Y%m%d-%H%M%S)"
  local dest="${app_backup_dir}/${date_tag}"
  mkdir -p "${dest}"

  info "Incremental backup of ${app} → ${dest}"

  local prev_dest=""
  if [[ -d "${app_backup_dir}" ]]; then
    prev_dest="$(find "${app_backup_dir}" -mindepth 1 -maxdepth 1 -type d \
      ! -name "${date_tag}" \
      | sort \
      | tail -1 || true)"
  fi

  _backup_dump_db "${cname}" "${db_type}" "${dest}"

  if [[ -n "${backup_data}" ]]; then
    mkdir -p "${dest}/data"
    local link_dest_arg=""
    if [[ -n "${prev_dest}" && -d "${prev_dest}/data" ]]; then
      link_dest_arg="--link-dest=${prev_dest}/data"
      info "Using previous snapshot for hardlinks: ${prev_dest}/data"
    fi
    info "Rsyncing data: ${backup_data}"
    # shellcheck disable=SC2086
    rsync -a ${link_dest_arg} "${backup_data}/" "${dest}/data/"
    ok "data/ synced"
  fi

  if [[ -n "${backup_storage}" && "${backup_storage}" != "null" ]]; then
    mkdir -p "${dest}/storage"
    local link_dest_arg=""
    if [[ -n "${prev_dest}" && -d "${prev_dest}/storage" ]]; then
      link_dest_arg="--link-dest=${prev_dest}/storage"
    fi
    info "Rsyncing storage: ${backup_storage}"
    # shellcheck disable=SC2086
    rsync -a ${link_dest_arg} "${backup_storage}/" "${dest}/storage/"
    ok "storage/ synced"
  fi

  _backup_log "OK  ${app}  incremental  ${dest}"
  ok "Incremental backup of ${app} to ${dest}"
}

_backup_one_app() {
  local app="$1" incremental="$2"

  local cname
  cname="$(docker ps -a \
    --filter "label=com.homekase.service=${app}" \
    --format '{{.Names}}' 2>/dev/null | head -1 || true)"

  if [[ -z "${cname}" ]]; then
    error "No container found for service '${app}'. Is it installed?"
    _backup_log "ERR ${app}  not found"
    return 1
  fi

  local backup_type
  backup_type="$(_backup_get_label "${cname}" "com.homekase.backup.type")"

  if [[ "${backup_type}" == "none" || -z "${backup_type}" ]]; then
    info "${app}: backup.type=none — skipping"
    return 0
  fi

  if "${incremental}"; then
    _backup_incremental "${app}" "${cname}"
  else
    _backup_snapshot "${app}" "${cname}"
  fi
}

cmd_backup() {
  local app_arg=""
  local incremental=false
  local arg

  for arg in "$@"; do
    case "${arg}" in
      --incremental) incremental=true ;;
      --*)           warn "Unknown flag: ${arg}" ;;
      *)             app_arg="${arg}" ;;
    esac
  done

  local backup_root
  backup_root="$(config_get 'paths.backup' 2>/dev/null || echo "/backup")"
  [[ "${backup_root}" == "null" || -z "${backup_root}" ]] && backup_root="/backup"
  BACKUP_LOG="${backup_root}/backup.log"
  mkdir -p "${backup_root}"

  _backup_acquire_lock
  trap '_backup_release_lock' EXIT INT TERM

  if [[ -n "${app_arg}" ]]; then
    _backup_one_app "${app_arg}" "${incremental}"
    local rc=$?
    _backup_release_lock
    trap - EXIT INT TERM
    return "${rc}"
  fi

  local all_containers
  all_containers="$(docker ps -a \
    --filter "label=com.homekase.service" \
    --format '{{.Names}}' 2>/dev/null || true)"

  if [[ -z "${all_containers}" ]]; then
    info "Nothing to backup — no homekase services found."
    _backup_log "INFO no services found — nothing to backup"
    _backup_release_lock
    trap - EXIT INT TERM
    return 0
  fi

  local cname errors=0
  while IFS= read -r cname; do
    [[ -z "${cname}" ]] && continue
    local svc
    svc="$(_backup_get_label "${cname}" "com.homekase.service")"
    [[ -z "${svc}" ]] && continue
    _backup_one_app "${svc}" "${incremental}" || (( errors++ )) || true
  done <<< "${all_containers}"

  if (( errors > 0 )); then
    warn "${errors} backup(s) failed. Check ${BACKUP_LOG} for details."
  fi

  _backup_release_lock
  trap - EXIT INT TERM
  return 0
}
