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
  "assistant:Local AI assistant (RAM-gated)"
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
  printf "%-18s %-42s %-12s %-8s %s\n" "NAME" "DESCRIPTION" "STATUS" "PORT" "URL"
  printf '%0.s─' {1..90}; echo

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
      port="-"
      url="-"
    fi

    printf "%-18s %-42s %-20s %-8s %s\n" \
      "${sname}" "${sdesc}" "${status}" "${port}" "${url}"
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
  # shellcheck source=/dev/null
  source "${HOMEKASE_DIR}/lib/services/${name}.sh"
  "remove_${name}"
}
