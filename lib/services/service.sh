#!/usr/bin/env bash
# shellcheck disable=SC2154  # GREEN/RESET set by common.sh
# Service dispatcher — list, add, remove.
# Sourced by the homekase main entry point after common.sh and config.sh.

HOMEKASE_DIR="${HOMEKASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=lib/services/_common.sh
source "${HOMEKASE_DIR}/lib/services/_common.sh"

# Registry: "name:description"
SERVICES=(
  "jellyfin:Media server (movies, TV, music)"
  "immich:Photo backup with AI tagging"
  "qbittorrent:Torrent client with optional VPN"
  "filebrowser:Web file manager for family sharing"
  "vikunja:Task management and calendar"
  "assistant:AI assistant with chat"
  "colibri:Local LLM inference (GLM-5.2 744B MoE)"
  "coder:Local coding LLM (Qwen2.5-Coder 7B)"
  "app:Server companion app"
  "navidrome:Music server (Spotify alternative)"
  "kamiyomu:Manga reader and downloader"
)

_service_description() {
  local name="$1" entry
  for entry in "${SERVICES[@]}"; do
    if [[ "${entry%%:*}" == "${name}" ]]; then
      echo "${entry#*:}"
      return 0
    fi
  done
  echo ""
}

_service_known() {
  local name="$1" entry
  for entry in "${SERVICES[@]}"; do
    [[ "${entry%%:*}" == "${name}" ]] && return 0
  done
  return 1
}

cmd_list() {
  header "Available services"
  printf "%-18s %-42s %-12s %s\n" "NAME" "DESCRIPTION" "STATUS" "URL"
  printf '%0.s─' {1..80}; echo

  local entry sname sdesc status port url ts_host ts_flag
  ts_host="$(config_get 'tailscale.hostname' 2>/dev/null || echo '')"

  for entry in "${SERVICES[@]}"; do
    sname="${entry%%:*}"
    sdesc="${entry#*:}"

    if config_app_installed "${sname}" 2>/dev/null; then
      status="${GREEN}installed${RESET}"
      port="$(config_app_get "${sname}" "port" 2>/dev/null || echo '-')"
      ts_flag="$(config_app_get "${sname}" "tailscale" 2>/dev/null || echo 'false')"
      if [[ "${ts_flag}" == "true" && -n "${ts_host}" ]]; then
        url="https://${ts_host}:${port}"
      elif [[ -n "${port}" && "${port}" != "null" && "${port}" != "-" ]]; then
        url="http://localhost:${port}"
      else
        url="-"
      fi
    else
      status="not installed"
      url="-"
    fi

    printf "%-18s %-42s %-20s %s\n" \
      "${sname}" "${sdesc}" "${status}" "${url}"
  done
  echo
}

cmd_add() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase add <name>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! _service_known "${name}"; then
    error "Unknown service: ${name}"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  # shellcheck source=/dev/null
  source "${HOMEKASE_DIR}/lib/services/${name}.sh"
  "deploy_${name}"
}

cmd_remove() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase remove <name>"
    exit 1
  fi
  if ! _service_known "${name}"; then
    error "Unknown service: ${name}"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi

  local port
  port="$(config_app_get "${name}" "port" 2>/dev/null || true)"

  # shellcheck source=/dev/null
  source "${HOMEKASE_DIR}/lib/services/${name}.sh"
  "remove_${name}"

  if [[ -n "${port}" && "${port}" != "null" ]]; then
    local ufw_status
    ufw_status="$(ufw status 2>/dev/null | head -1 || true)"
    if [[ "${ufw_status}" == "Status: active" ]]; then
      local ufw_rules
      ufw_rules="$(ufw status 2>/dev/null || true)"
      if echo "${ufw_rules}" | grep -q "^${port}/tcp"; then
        warn "Port ${port}/tcp is still open in UFW."
        warn "Run: homekase server firewall close ${port}"
      fi
    fi
  fi
}

cmd_logs() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase logs <service>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! config_app_installed "${name}" 2>/dev/null; then
    error "Service ${name} is not installed"
    exit 1
  fi
  shift

  if systemctl is-active --quiet "homekase-${name}" 2>/dev/null; then
    journalctl -u "homekase-${name}" "$@"
    return
  fi

  local repo_dir="${HOMEKASE_REPO_DIR}/services/${name}"
  local deploy_dir="${HOMELAB_DIR}/${name}"
  local compose_file=""
  local env_file=""

  if [[ -f "${repo_dir}/docker-compose.yml" ]]; then
    compose_file="${repo_dir}/docker-compose.yml"
    [[ -f "${deploy_dir}/.env" ]] && env_file="--env-file ${deploy_dir}/.env"
  elif [[ -f "${deploy_dir}/docker-compose.yml" ]]; then
    compose_file="${deploy_dir}/docker-compose.yml"
  else
    error "No compose file found for ${name}"
    exit 1
  fi

  docker compose -f "${compose_file}" ${env_file} logs "$@"
}

cmd_restart() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase restart <service>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! config_app_installed "${name}" 2>/dev/null; then
    error "Service ${name} is not installed"
    exit 1
  fi

  require_root
  header "Restarting ${name}"

  local repo_dir="${HOMEKASE_REPO_DIR}/services/${name}"
  local deploy_dir="${HOMELAB_DIR}/${name}"

  # Native systemd service
  if systemctl is-active --quiet "homekase-${name}" 2>/dev/null; then
    systemctl restart "homekase-${name}"
    ok "${name} restarted."
    return
  fi

  # Must have a compose file somewhere
  if [[ ! -f "${deploy_dir}/docker-compose.yml" && ! -f "${repo_dir}/docker-compose.yml" ]]; then
    error "No compose file found for ${name}"
    exit 1
  fi

  local env_file=""
  [[ -f "${deploy_dir}/.env" ]] && env_file="--env-file ${deploy_dir}/.env"
  local compose_file="${deploy_dir}/docker-compose.yml"
  [[ -f "${repo_dir}/docker-compose.yml" ]] && compose_file="${repo_dir}/docker-compose.yml"

  docker compose -f "${compose_file}" ${env_file} up -d

  ok "${name} restarted."
}

_find_compose_file() {
  local name="$1"
  local deploy_dir="${HOMELAB_DIR}/${name}"
  local repo_dir="${HOMEKASE_REPO_DIR}/services/${name}"

  if [[ -f "${deploy_dir}/docker-compose.yml" ]]; then
    echo "${deploy_dir}/docker-compose.yml"
  elif [[ -f "${repo_dir}/docker-compose.yml" ]]; then
    echo "${repo_dir}/docker-compose.yml"
  fi
}

_find_env_file() {
  local name="$1"
  local deploy_dir="${HOMELAB_DIR}/${name}"
  local env_file=""
  [[ -f "${deploy_dir}/.env" ]] && echo "${deploy_dir}/.env"
}

cmd_pause() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase pause <service>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! config_app_installed "${name}" 2>/dev/null; then
    error "Service ${name} is not installed"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi

  require_root
  header "Pausing ${name}"

  if systemctl is-active --quiet "homekase-${name}" 2>/dev/null; then
    systemctl stop "homekase-${name}"
    ok "${name} paused."
    return
  fi

  local compose_file env_file=""
  compose_file="$(_find_compose_file "${name}")"
  if [[ -z "${compose_file}" ]]; then
    error "No compose file found for ${name}"
    exit 1
  fi

  local env_path
  env_path="$(_find_env_file "${name}")"
  [[ -n "${env_path}" ]] && env_file="--env-file ${env_path}"

  docker compose -f "${compose_file}" ${env_file} stop
  ok "${name} paused."
}

cmd_resume() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase resume <service>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! config_app_installed "${name}" 2>/dev/null; then
    error "Service ${name} is not installed"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi

  require_root
  header "Resuming ${name}"

  if systemctl is-active --quiet "homekase-${name}" 2>/dev/null; then
    info "${name} is already running."
    return
  fi

  local compose_file env_file=""
  compose_file="$(_find_compose_file "${name}")"

  if [[ -f "/etc/systemd/system/homekase-${name}.service" ]]; then
    systemctl start "homekase-${name}"
    ok "${name} resumed."
    return
  fi

  if [[ -z "${compose_file}" ]]; then
    error "No compose file found for ${name}"
    exit 1
  fi

  local env_path
  env_path="$(_find_env_file "${name}")"
  [[ -n "${env_path}" ]] && env_file="--env-file ${env_path}"

  docker compose -f "${compose_file}" ${env_file} start
  ok "${name} resumed."
}

cmd_update_service() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    error "Usage: homekase update <service>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! config_app_installed "${name}" 2>/dev/null; then
    error "Service ${name} is not installed"
    exit 1
  fi

  require_root
  header "Updating ${name}"

  local repo_dir="${HOMEKASE_REPO_DIR}/services/${name}"
  local deploy_dir="${HOMELAB_DIR}/${name}"

  # Native systemd service
  if systemctl is-active --quiet "homekase-${name}" 2>/dev/null; then
    info "Updating native service ${name}..."
    if [[ -d "${repo_dir}" ]]; then
      cp -r "${repo_dir}/main.py" "${repo_dir}/templates" "${deploy_dir}/" 2>/dev/null || true
      systemctl restart "homekase-${name}"
      ok "${name} updated."
      return
    fi
  fi

  # Must have a compose file somewhere
  if [[ ! -f "${deploy_dir}/docker-compose.yml" && ! -f "${repo_dir}/docker-compose.yml" ]]; then
    error "No compose file found for ${name}"
    exit 1
  fi

  # Regenerate config files from the latest service template
  source "${HOMEKASE_DIR}/lib/services/${name}.sh"

  stop_service "${name}"

  local update_func="_update_${name}"
  if declare -F "${update_func}" &>/dev/null; then
    "${update_func}"
  else
    info "No update logic defined for ${name}, reusing existing config."
  fi

  # Pull latest images and restart
  local env_file=""
  [[ -f "${deploy_dir}/.env" ]] && env_file="--env-file ${deploy_dir}/.env"
  local compose_file="${deploy_dir}/docker-compose.yml"
  [[ -f "${repo_dir}/docker-compose.yml" ]] && compose_file="${repo_dir}/docker-compose.yml"

  docker compose -f "${compose_file}" ${env_file} pull
  docker compose -f "${compose_file}" ${env_file} up -d

  ok "${name} updated."
}
