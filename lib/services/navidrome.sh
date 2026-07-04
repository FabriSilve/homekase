#!/usr/bin/env bash
# Navidrome music server service installer.
# Sourced by lib/services/service.sh on `homekase add navidrome`.

deploy_navidrome() {
  require_root
  header "Installing Navidrome"

  local PORT DATA_PATH MUSIC_PATH TS NAVIDROME_URL BIND_ADDR

  PORT="$(port_wizard "navidrome" 1)"
  DATA_PATH="$(ask_input "Navidrome config/data path" "/data/config/navidrome")"
  MUSIC_PATH="$(ask_input "Music library path" "/storage/music")"
  TS="$(tailscale_serve_setup "${PORT}")"
  NAVIDROME_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "navidrome"

  write_compose_file "navidrome" "services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:4533\"
    volumes:
      - \${DATA_PATH}:/data
      - \${MUSIC_PATH}:/music:ro
    environment:
      ND_SERVERPORT: \"4533\"
      ND_MUSICFOLDER: /music
      ND_DATAFOLDER: /data
      ND_ENABLEDOWNLOADS: \"true\"
    networks:
      - homelab-net
    labels:
      com.homekase.service: navidrome
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "navidrome" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MUSIC_PATH=${MUSIC_PATH}
TS=${TS}
NAVIDROME_URL=${NAVIDROME_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}" "${MUSIC_PATH}"

  start_service "navidrome"

  config_app_set navidrome installed    true
  config_app_set navidrome port         "${PORT}"
  config_app_set navidrome data_path    "${DATA_PATH}"
  config_app_set navidrome storage_path "${MUSIC_PATH}"
  config_app_set navidrome tailscale    "${TS}"

  ok "Navidrome running on port ${PORT}  →  ${NAVIDROME_URL}"
}

_update_navidrome() {
  local PORT DATA_PATH MUSIC_PATH TS NAVIDROME_URL BIND_ADDR

  PORT="$(config_app_get navidrome port)"
  DATA_PATH="$(config_app_get navidrome data_path)"
  MUSIC_PATH="$(config_app_get navidrome storage_path)"
  TS="$(config_app_get navidrome tailscale)"

  NAVIDROME_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "navidrome"

  write_compose_file "navidrome" "services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:4533\"
    volumes:
      - \${DATA_PATH}:/data
      - \${MUSIC_PATH}:/music:ro
    environment:
      ND_SERVERPORT: \"4533\"
      ND_MUSICFOLDER: /music
      ND_DATAFOLDER: /data
      ND_ENABLEDOWNLOADS: \"true\"
    networks:
      - homelab-net
    labels:
      com.homekase.service: navidrome
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "navidrome" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MUSIC_PATH=${MUSIC_PATH}
TS=${TS}
NAVIDROME_URL=${NAVIDROME_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}" "${MUSIC_PATH}"
}

remove_navidrome() {
  require_root
  header "Removing Navidrome"

  local port data_path music_path
  port="$(config_app_get navidrome port 2>/dev/null || true)"
  data_path="$(config_app_get navidrome data_path 2>/dev/null || true)"
  music_path="$(config_app_get navidrome storage_path 2>/dev/null || true)"

  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "navidrome"

  if [[ -n "${data_path}" && -d "${data_path}" ]]; then
    if ask_confirm "Also delete music database/config at ${data_path}?"; then
      rm -rf "${data_path}"
      ok "Removed ${data_path}"
    else
      info "Data kept at ${data_path}"
    fi
  fi

  if [[ -n "${music_path}" && -d "${music_path}" ]]; then
    info "Music library kept at ${music_path} (not touched)"
  fi

  config_app_remove navidrome
  ok "Navidrome removed."
}
