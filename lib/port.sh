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

  info "Opening port ${port}/tcp for ${svc}..."
  ufw allow "${port}/tcp"
  ok "Port ${port}/tcp open — ${svc} accessible on LAN."
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

  info "Closing port ${port}/tcp for ${svc}..."
  ufw delete allow "${port}/tcp" 2>/dev/null || true
  ok "Port ${port}/tcp closed — ${svc} no longer accessible on LAN."
}
