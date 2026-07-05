#!/usr/bin/env bash
# Filebrowser service installer.
# Sourced by lib/services/service.sh on `homekase add filebrowser`.

deploy_filebrowser() {
  require_root
  header "Installing Filebrowser"

  local PORT STORAGE_PATH TS BIND_ADDR

  PORT="$(port_wizard "filebrowser" 1)"
  STORAGE_PATH="$(ask_input "Storage root to browse" "/storage")"
  TS="$(tailscale_serve_setup "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "filebrowser"

  write_compose_file "filebrowser" "services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:80\"
    volumes:
      - \${STORAGE_PATH}:/srv
      - ${HOMELAB_DIR}/filebrowser/filebrowser.db:/database.db
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
TS=${TS}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${STORAGE_PATH}"
  rm -f "${HOMELAB_DIR}/filebrowser/filebrowser.db"
  touch "${HOMELAB_DIR}/filebrowser/filebrowser.db"
  chmod 666 "${HOMELAB_DIR}/filebrowser/filebrowser.db"

  start_service "filebrowser"

  config_app_set filebrowser installed    true
  config_app_set filebrowser port         "${PORT}"
  config_app_set filebrowser storage_path "${STORAGE_PATH}"
  config_app_set filebrowser tailscale    "${TS}"

  ok "Filebrowser running on port ${PORT}  →  $(service_url "${PORT}")"
  info "Login with admin / <check docker logs for password>"
}

_update_filebrowser() {
  local PORT STORAGE_PATH TS BIND_ADDR

  PORT="$(config_app_get filebrowser port)"
  STORAGE_PATH="$(config_app_get filebrowser storage_path)"
  TS="$(config_app_get filebrowser tailscale)"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "filebrowser"

  write_compose_file "filebrowser" "services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:80\"
    volumes:
      - \${STORAGE_PATH}:/srv
      - ${HOMELAB_DIR}/filebrowser/filebrowser.db:/database.db
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
TS=${TS}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${STORAGE_PATH}"
  touch "${HOMELAB_DIR}/filebrowser/filebrowser.db"
  chmod 666 "${HOMELAB_DIR}/filebrowser/filebrowser.db"
}

remove_filebrowser() {
  require_root
  header "Removing Filebrowser"
  local port
  port="$(config_app_get filebrowser port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "filebrowser"
  config_app_remove filebrowser
  ok "Filebrowser removed."
}
