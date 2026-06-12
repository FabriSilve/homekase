#!/usr/bin/env bash
# Filebrowser service installer.
# Sourced by lib/services/service.sh on `homekase add filebrowser`.

deploy_filebrowser() {
  require_root
  header "Installing Filebrowser"

  local PORT STORAGE_PATH ADMIN_PASSWORD TS

  PORT="$(port_wizard "filebrowser" 1)"
  STORAGE_PATH="$(ask_input "Storage root to browse" "/storage")"
  ADMIN_PASSWORD="$(ask_input "Admin password (shown once, stored in .env)" "")"
  TS="$(tailscale_serve_setup "${PORT}")"

  write_service_dir "filebrowser"

  write_compose_file "filebrowser" "services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    ports:
      - \"\${PORT}:80\"
    volumes:
      - \${STORAGE_PATH}:/srv
      - ${HOMELAB_DIR}/filebrowser/filebrowser.db:/database.db
    environment:
      FB_PASSWORD: \${ADMIN_PASSWORD}
    command: --database /database.db --root /srv --port 80 --address 0.0.0.0
    networks:
      - homelab-net
    labels:
      com.homekase.service: filebrowser
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: ${HOMELAB_DIR}/filebrowser/filebrowser.db
      com.homekase.backup.db-type: sqlite

networks:
  homelab-net:
    external: true"

  write_env_file "filebrowser" "PORT=${PORT}
STORAGE_PATH=${STORAGE_PATH}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
TS=${TS}"

  mkdir -p "${STORAGE_PATH}"

  start_service "filebrowser"

  config_app_set filebrowser installed    true
  config_app_set filebrowser port         "${PORT}"
  config_app_set filebrowser storage_path "${STORAGE_PATH}"
  config_app_set filebrowser tailscale    "${TS}"

  ok "Filebrowser running on port ${PORT}  →  http://localhost:${PORT}"
  info "Login with admin / <your chosen password>"
}

remove_filebrowser() {
  require_root
  header "Removing Filebrowser"
  remove_service_dir "filebrowser"
  config_app_set filebrowser installed false
  ok "Filebrowser removed."
}
