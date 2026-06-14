#!/usr/bin/env bash
# shellcheck disable=SC2154  # HOMEKASE_CONFIG set by sourcing script (config.sh)
# Shared helpers for all service installers.
# Sourced by lib/services/service.sh after common.sh and config.sh are loaded.

HOMELAB_DIR="${HOMELAB_DIR:-/opt/homekase}"
DEFAULT_FIRST_PORT=4000
PORT_STEP=10

# Returns the next suggested free port by reading all app ports from config,
# taking the maximum, and adding PORT_STEP. Falls back to DEFAULT_FIRST_PORT.
next_available_port() {
  local max_port=$(( DEFAULT_FIRST_PORT - PORT_STEP ))
  local port_list
  port_list="$(yq '.apps.*.port // ""' "${HOMEKASE_CONFIG}" 2>/dev/null)" || true
  while IFS= read -r p; do
    [[ "${p}" =~ ^[0-9]+$ ]] || continue
    (( p > max_port )) && max_port="${p}"
  done <<< "${port_list}"
  echo $(( max_port + PORT_STEP ))
}

# Interactively asks user to pick a start port for a service.
# Usage: port_wizard <service_name> <num_ports>
# Prints the chosen port number to stdout.
port_wizard() {
  local service_name="$1"
  local num_ports="${2:-1}"
  local suggestion
  suggestion="$(next_available_port)"
  local chosen
  chosen="$(ask_input "Port for ${service_name} (needs ${num_ports} port(s))" "${suggestion}")"
  if ! [[ "${chosen}" =~ ^[0-9]+$ ]]; then
    error "Invalid port: ${chosen}"
    exit 1
  fi
  # shellcheck disable=SC2312
  if ss -tlnp 2>/dev/null | grep -q ":${chosen} "; then
    warn "Port ${chosen} appears to be in use. Proceeding anyway."
  fi
  echo "${chosen}"
}

# Sets up Tailscale Serve for a given port if Tailscale is installed.
# Usage: tailscale_serve_setup <port>
# Prints "true" or "false" to stdout.
tailscale_serve_setup() {
  local port="$1"
  local ts_installed
  ts_installed="$(config_get 'tailscale.installed' 2>/dev/null || echo 'false')"
  if [[ "${ts_installed}" != "true" ]]; then
    echo "false"
    return 0
  fi
  if ask_confirm "Expose port ${port} via Tailscale Serve (HTTPS)?"; then
    tailscale serve --bg --https="${port}" http://localhost:"${port}" >&2 \
      || warn "tailscale serve failed — check tailscale status"
    echo "true"
  else
    echo "false"
  fi
}

# Removes a Tailscale Serve mapping for a given port.
# Usage: tailscale_serve_remove <port>
tailscale_serve_remove() {
  local port="$1"
  local ts_installed
  ts_installed="$(config_get 'tailscale.installed' 2>/dev/null || echo 'false')"
  if [[ "${ts_installed}" != "true" ]]; then
    return 0
  fi
  tailscale serve --https="${port}" off || warn "failed to remove tailscale serve mapping for port ${port}"
}

# Build the external-facing service URL based on Tailscale config.
# Usage: service_url <port>
# Prints "https://<tailscale-hostname>:<port>" when tailscale is set up,
# otherwise prints "http://localhost:<port>".
service_url() {
  local port="$1"
  local ts_host
  ts_host="$(config_get 'tailscale.hostname' 2>/dev/null || true)"
  if [[ -n "${ts_host}" ]]; then
    echo "https://${ts_host}:${port}"
  else
    echo "http://localhost:${port}"
  fi
}

# Creates /opt/homekase/<name>/ directory.
write_service_dir() {
  local name="$1"
  mkdir -p "${HOMELAB_DIR}/${name}"
}

# Writes /opt/homekase/<name>/.env from the given content string.
write_env_file() {
  local name="$1"
  local content="$2"
  printf '%s\n' "${content}" > "${HOMELAB_DIR}/${name}/.env"
}

# Writes /opt/homekase/<name>/docker-compose.yml from the given content string.
write_compose_file() {
  local name="$1"
  local content="$2"
  printf '%s\n' "${content}" > "${HOMELAB_DIR}/${name}/docker-compose.yml"
}

# Starts a service via Docker Compose.
start_service() {
  local name="$1"
  docker network create homelab-net 2>/dev/null || true
  docker compose -f "${HOMELAB_DIR}/${name}/docker-compose.yml" up -d
}

# Stops a service via Docker Compose.
stop_service() {
  local name="$1"
  docker compose -f "${HOMELAB_DIR}/${name}/docker-compose.yml" down 2>/dev/null || true
}

# Stops a service and optionally removes its directory.
remove_service_dir() {
  local name="$1"
  stop_service "${name}"
  if ask_confirm "Also delete data in ${HOMELAB_DIR}/${name}?"; then
    rm -rf "${HOMELAB_DIR:?}/${name}"
    ok "Removed ${HOMELAB_DIR}/${name}"
  else
    info "Data kept at ${HOMELAB_DIR}/${name}"
  fi
}
