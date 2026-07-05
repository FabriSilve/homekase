#!/usr/bin/env bash
# shellcheck disable=SC2154  # BOLD/RESET set by common.sh

_port_usage() {
  echo
  printf "%b\n" "${BOLD}USAGE${RESET}"
  echo "  homekase open <service>    Open service port in UFW for LAN access"
  echo "  homekase close <service>   Close service port in UFW"
  echo
}

_port_find_container() {
  local svc="$1"
  docker ps -a \
    --filter "label=com.homekase.service=${svc}" \
    --format '{{.Names}}' 2>/dev/null | head -1 || true
}

_port_get_port() {
  local cname="$1"
  docker inspect "${cname}" \
    --format '{{index .Config.Labels "com.homekase.port"}}' 2>/dev/null || true
}

HOMELAB_DIR="${HOMELAB_DIR:-/opt/homekase}"

_restart_service() {
  local name="$1"
  local deploy_dir="${HOMELAB_DIR}/${name}"
  local repo_dir="${HOMEKASE_REPO_DIR:-${HOMELAB_DIR}}/services/${name}"

  if systemctl is-active --quiet "homekase-${name}" 2>/dev/null; then
    systemctl restart "homekase-${name}"
    return 0
  fi

  local compose_file=""
  [[ -f "${deploy_dir}/docker-compose.yml" ]] && compose_file="${deploy_dir}/docker-compose.yml"
  [[ -z "${compose_file}" && -f "${repo_dir}/docker-compose.yml" ]] && compose_file="${repo_dir}/docker-compose.yml"

  if [[ -z "${compose_file}" ]]; then
    error "No compose file found for ${name}"
    return 1
  fi

  local env_file=""
  [[ -f "${deploy_dir}/.env" ]] && env_file="--env-file ${deploy_dir}/.env"

  docker compose -f "${compose_file}" ${env_file} up -d
}

_port_ufw_active() {
  local ufw_status
  ufw_status="$(ufw status 2>/dev/null | head -1 || true)"
  [[ "${ufw_status}" == "Status: active" ]]
}

_port_resolve() {
  local svc="$1"
  local cname
  cname="$(_port_find_container "${svc}")"
  if [[ -z "${cname}" ]]; then
    error "No container found for service '${svc}'. Is it installed?"
    return 1
  fi
  local port
  port="$(_port_get_port "${cname}")"
  if [[ -z "${port}" || "${port}" == "null" ]]; then
    error "Service '${svc}' has no port label (com.homekase.port)."
    return 1
  fi
  echo "${port}"
}

cmd_open() {
  local svc="${1:-}"
  if [[ -z "${svc}" || "${svc}" == "--help" || "${svc}" == "-h" ]]; then
    _port_usage; return 0
  fi

  local port
  port="$(_port_resolve "${svc}")" || return 1

  if ! _port_ufw_active; then
    warn "UFW is not active — no firewall rule added."
    info "Port ${port} is accessible on LAN without restriction."
    return 0
  fi

  require_root
  info "Opening port ${port}/tcp for ${svc}..."
  ufw allow "${port}/tcp"
  ok "Port ${port}/tcp open — ${svc} accessible on LAN."
}

_cmd_expose_common() {
  local svc="$1"
  if ! config_app_installed "${svc}" 2>/dev/null; then
    error "Service '${svc}' is not installed."
    return 1
  fi
  local port
  port="$(config_app_get "${svc}" "port" 2>/dev/null || true)"
  if [[ -z "${port}" || "${port}" == "null" ]]; then
    port="$(_port_resolve "${svc}")" || return 1
  fi
  echo "${port}"
}

cmd_expose() {
  local svc="${1:-}"
  if [[ -z "${svc}" || "${svc}" == "--help" || "${svc}" == "-h" ]]; then
    echo
    echo -e "${BOLD}USAGE${RESET}"
    echo "  homekase expose <service>    Expose service on LAN (bypass Tailscale)"
    echo
    return 0
  fi

  local port
  port="$(_cmd_expose_common "${svc}")" || return 1

  local exposed
  exposed="$(config_app_get "${svc}" "exposed" 2>/dev/null || echo 'false')"
  if [[ "${exposed}" == "true" ]]; then
    warn "Service '${svc}' is already exposed on LAN."
    return 0
  fi

  require_root
  header "Exposing ${svc} on LAN"

  local env_file="${HOMELAB_DIR}/${svc}/.env"
  if [[ -f "${env_file}" ]]; then
    if grep -q "^BIND_ADDR=127.0.0.1:" "${env_file}"; then
      sed -i 's/^BIND_ADDR=127.0.0.1:/BIND_ADDR=/' "${env_file}"
      info "Removed 127.0.0.1 bind restriction from .env"
    fi
  fi

  _restart_service "${svc}"

  if _port_ufw_active; then
    ufw allow "${port}/tcp" 2>/dev/null || true
    info "Opened port ${port}/tcp in UFW."
  fi

  config_app_set "${svc}" "exposed" "true"
  ok "Service '${svc}' is now exposed on LAN (port ${port})."
}

cmd_unexpose() {
  local svc="${1:-}"
  if [[ -z "${svc}" || "${svc}" == "--help" || "${svc}" == "-h" ]]; then
    echo
    echo -e "${BOLD}USAGE${RESET}"
    echo "  homekase unexpose <service>  Remove LAN exposure, restore Tailscale-only access"
    echo
    return 0
  fi

  local port
  port="$(_cmd_expose_common "${svc}")" || return 1

  local exposed
  exposed="$(config_app_get "${svc}" "exposed" 2>/dev/null || echo 'false')"
  if [[ "${exposed}" != "true" ]]; then
    warn "Service '${svc}' is not currently exposed on LAN."
    return 0
  fi

  require_root
  header "Removing LAN exposure for ${svc}"

  local ts_installed
  ts_installed="$(config_get 'tailscale.installed' 2>/dev/null || echo 'false')"

  local env_file="${HOMELAB_DIR}/${svc}/.env"
  if [[ -f "${env_file}" ]]; then
    if grep -q "^BIND_ADDR=$" "${env_file}"; then
      if [[ "${ts_installed}" == "true" ]]; then
        sed -i 's/^BIND_ADDR=$/BIND_ADDR=127.0.0.1:/' "${env_file}"
        info "Restored 127.0.0.1 bind restriction in .env"
      fi
    fi
  fi

  _restart_service "${svc}"

  if _port_ufw_active; then
    ufw delete allow "${port}/tcp" 2>/dev/null || true
    info "Closed port ${port}/tcp in UFW."
  fi

  config_app_set "${svc}" "exposed" "false"
  ok "Service '${svc}' is no longer exposed on LAN."
}

cmd_close() {
  local svc="${1:-}"
  if [[ -z "${svc}" || "${svc}" == "--help" || "${svc}" == "-h" ]]; then
    _port_usage; return 0
  fi

  local port
  port="$(_port_resolve "${svc}")" || return 1

  if ! _port_ufw_active; then
    warn "UFW is not active — no rule to remove."
    return 0
  fi

  require_root
  info "Closing port ${port}/tcp for ${svc}..."
  ufw delete allow "${port}/tcp" 2>/dev/null || true
  ok "Port ${port}/tcp closed — ${svc} no longer accessible on LAN."
}
