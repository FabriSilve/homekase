#!/usr/bin/env bash
# Jellyfin service installer.
# Sourced by lib/services/service.sh on `homekase add jellyfin`.

deploy_jellyfin() {
  require_root
  header "Installing Jellyfin"

  local PORT DATA_PATH MEDIA_PATH TS JELLYFIN_URL BIND_ADDR

  PORT="$(port_wizard "jellyfin" 1)"
  DATA_PATH="$(ask_input "Jellyfin config/data path" "/data/config/jellyfin")"
  MEDIA_PATH="$(ask_input "Media storage path" "/storage/media")"
  TS="$(tailscale_serve_setup "${PORT}")"
  JELLYFIN_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "jellyfin"

  write_compose_file "jellyfin" "services:
  jellyfin:
    image: jellyfin/jellyfin:10
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:8096\"
    volumes:
      - \${DATA_PATH}:/config
      - \${MEDIA_PATH}:/media:ro
    networks:
      - homelab-net
    labels:
      com.homekase.service: jellyfin
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "jellyfin" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MEDIA_PATH=${MEDIA_PATH}
TS=${TS}
JELLYFIN_URL=${JELLYFIN_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}" "${MEDIA_PATH}"

  start_service "jellyfin"

  config_app_set jellyfin installed true
  config_app_set jellyfin port "${PORT}"
  config_app_set jellyfin data_path "${DATA_PATH}"
  config_app_set jellyfin storage_path "${MEDIA_PATH}"
  config_app_set jellyfin tailscale "${TS}"

  ok "Jellyfin running on port ${PORT}  →  ${JELLYFIN_URL}"
}

_update_jellyfin() {
  local PORT DATA_PATH MEDIA_PATH TS JELLYFIN_URL BIND_ADDR

  PORT="$(config_app_get jellyfin port)"
  DATA_PATH="$(config_app_get jellyfin data_path)"
  MEDIA_PATH="$(config_app_get jellyfin storage_path)"
  TS="$(config_app_get jellyfin tailscale)"

  JELLYFIN_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "jellyfin"

  write_compose_file "jellyfin" "services:
  jellyfin:
    image: jellyfin/jellyfin:10
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:8096\"
    volumes:
      - \${DATA_PATH}:/config
      - \${MEDIA_PATH}:/media:ro
    networks:
      - homelab-net
    labels:
      com.homekase.service: jellyfin
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "jellyfin" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MEDIA_PATH=${MEDIA_PATH}
TS=${TS}
JELLYFIN_URL=${JELLYFIN_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}" "${MEDIA_PATH}"
}

remove_jellyfin() {
  require_root
  header "Removing Jellyfin"
  local port
  port="$(config_app_get jellyfin port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "jellyfin"
  config_app_remove jellyfin
  ok "Jellyfin removed."
}
