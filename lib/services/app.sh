#!/usr/bin/env bash
# Server dashboard service installer.
# Sourced by lib/services/service.sh on `homekase add app`.
# Deploys from services/app/ within the homekase repo.

deploy_app() {
  require_root
  header "Installing Server Dashboard"

  local PORT TS BIND_ADDR APP_URL
  PORT="$(port_wizard "app" 1)"
  TS="$(tailscale_serve_setup "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"
  APP_URL="$(service_url "${PORT}")"

  local APP_DIR="${HOMEKASE_REPO_DIR}/services/app"
  local DEPLOY_DIR="${HOMELAB_DIR}/app"

  mkdir -p "${DEPLOY_DIR}"

  write_env_file "app" "PORT=${PORT}
TS=${TS}
BIND_ADDR=${BIND_ADDR}
APP_URL=${APP_URL}"

  info "Building dashboard image..."
  docker compose -f "${APP_DIR}/docker-compose.yml" build

  info "Starting dashboard..."
  docker compose -f "${APP_DIR}/docker-compose.yml" up -d

  config_app_set app installed true
  config_app_set app port      "${PORT}"
  config_app_set app tailscale "${TS}"

  ok "Dashboard running on port ${PORT}  →  ${APP_URL}"
}

remove_app() {
  require_root
  header "Removing Server Dashboard"
  local port
  port="$(config_app_get app port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"

  local APP_DIR="${HOMEKASE_REPO_DIR}/services/app"
  if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
    docker compose -f "${APP_DIR}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
  fi

  remove_service_dir "app"
  config_app_remove app
  ok "Dashboard removed."
}
