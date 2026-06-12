#!/usr/bin/env bash
# Vikunja service installer (all-in-one with SQLite).
# Sourced by lib/services/service.sh on `homekase add vikunja`.

deploy_vikunja() {
  require_root
  header "Installing Vikunja"

  local PORT DATA_PATH TS

  PORT="$(port_wizard "vikunja" 1)"
  DATA_PATH="$(ask_input "Vikunja data path" "/data/config/vikunja")"
  TS="$(tailscale_serve_setup "${PORT}")"

  write_service_dir "vikunja"

  write_compose_file "vikunja" "services:
  vikunja:
    image: vikunja/vikunja:latest
    container_name: vikunja
    restart: unless-stopped
    ports:
      - \"\${PORT}:3456\"
    volumes:
      - \${DATA_PATH}:/app/vikunja/files
    environment:
      VIKUNJA_DATABASE_TYPE: sqlite
      VIKUNJA_DATABASE_PATH: /app/vikunja/files/vikunja.db
      VIKUNJA_SERVICE_FRONTENDURL: http://localhost:\${PORT}
      VIKUNJA_SERVICE_PUBLICURL: http://localhost:\${PORT}
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
TS=${TS}"

  mkdir -p "${DATA_PATH}"

  start_service "vikunja"

  config_app_set vikunja installed  true
  config_app_set vikunja port       "${PORT}"
  config_app_set vikunja data_path  "${DATA_PATH}"
  config_app_set vikunja tailscale  "${TS}"

  ok "Vikunja running on port ${PORT}  →  http://localhost:${PORT}"
}

remove_vikunja() {
  require_root
  header "Removing Vikunja"
  remove_service_dir "vikunja"
  config_app_set vikunja installed false
  ok "Vikunja removed."
}
