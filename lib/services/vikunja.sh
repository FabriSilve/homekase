#!/usr/bin/env bash
# Vikunja service installer (all-in-one with SQLite).
# Sourced by lib/services/service.sh on `homekase add vikunja`.

deploy_vikunja() {
  require_root
  header "Installing Vikunja"

  local PORT DATA_PATH TS VIKUNJA_URL BIND_ADDR

  PORT="$(port_wizard "vikunja" 1)"
  DATA_PATH="$(ask_input "Vikunja data path" "/data/config/vikunja")"
  TS="$(tailscale_serve_setup "${PORT}")"
  VIKUNJA_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "vikunja"

  write_compose_file "vikunja" "services:
  vikunja:
    image: vikunja/vikunja:latest
    container_name: vikunja
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:3456\"
    volumes:
      - \${DATA_PATH}:/app/vikunja/files
    environment:
      VIKUNJA_DATABASE_TYPE: sqlite
      VIKUNJA_DATABASE_PATH: /app/vikunja/files/vikunja.db
      VIKUNJA_SERVICE_FRONTENDURL: \${VIKUNJA_URL}
      VIKUNJA_SERVICE_PUBLICURL: \${VIKUNJA_URL}
    networks:
      - homelab-net
    labels:
      com.homekase.service: vikunja
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: sqlite

networks:
  homelab-net:
    external: true"

  write_env_file "vikunja" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
TS=${TS}
VIKUNJA_URL=${VIKUNJA_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}"
  chown -R 1000:0 "${DATA_PATH}"

  start_service "vikunja"

  config_app_set vikunja installed  true
  config_app_set vikunja port       "${PORT}"
  config_app_set vikunja data_path  "${DATA_PATH}"
  config_app_set vikunja tailscale  "${TS}"

  ok "Vikunja running on port ${PORT}  →  ${VIKUNJA_URL}"
}

remove_vikunja() {
  require_root
  header "Removing Vikunja"
  local port
  port="$(config_app_get vikunja port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "vikunja"
  config_app_remove vikunja
  ok "Vikunja removed."
}
