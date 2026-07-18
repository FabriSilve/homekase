#!/usr/bin/env bash
# KamiYomu manga reader and downloader.
# Sourced by lib/services/service.sh on `homekase add kamiyomu`.

deploy_kamiyomu() {
  require_root
  header "Installing KamiYomu"

  local PORT DATA_PATH MANGA_PATH TS KAMIYOMU_URL BIND_ADDR

  PORT="$(port_wizard "kamiyomu" 1)"
  DATA_PATH="$(ask_input "KamiYomu data path (db/agents/logs)" "/data/kamiyomu")"
  MANGA_PATH="$(ask_input "Manga storage path" "/storage/manga")"
  TS="$(tailscale_serve_setup "${PORT}")"
  KAMIYOMU_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "kamiyomu"

  write_compose_file "kamiyomu" "services:
  kamiyomu:
    image: marcoscostadev/kamiyomu:latest
    container_name: kamiyomu
    restart: unless-stopped
    healthcheck:
      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:8080/healthz\"]
      interval: 30s
      timeout: 10s
      retries: 3
    ports:
      - \"\${BIND_ADDR}\${PORT}:8080\"
    volumes:
      - \${DATA_PATH}/db:/db
      - \${DATA_PATH}/agents:/agents
      - \${DATA_PATH}/logs:/logs
      - /etc/localtime:/etc/localtime:ro
      - \${MANGA_PATH}:/manga
    networks:
      - homelab-net
    labels:
      com.homekase.service: kamiyomu
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.storage: \"\${MANGA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "kamiyomu" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MANGA_PATH=${MANGA_PATH}
TS=${TS}
KAMIYOMU_URL=${KAMIYOMU_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}/db" "${DATA_PATH}/agents" "${DATA_PATH}/logs" "${MANGA_PATH}"

  start_service "kamiyomu"

  config_app_set kamiyomu installed true
  config_app_set kamiyomu port "${PORT}"
  config_app_set kamiyomu data_path "${DATA_PATH}"
  config_app_set kamiyomu storage_path "${MANGA_PATH}"
  config_app_set kamiyomu tailscale "${TS}"

  ok "KamiYomu running on port ${PORT}  →  ${KAMIYOMU_URL}"
}

_update_kamiyomu() {
  local PORT DATA_PATH MANGA_PATH TS KAMIYOMU_URL BIND_ADDR

  PORT="$(config_app_get kamiyomu port)"
  DATA_PATH="$(config_app_get kamiyomu data_path)"
  MANGA_PATH="$(config_app_get kamiyomu storage_path)"
  TS="$(config_app_get kamiyomu tailscale)"

  KAMIYOMU_URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "kamiyomu"

  write_compose_file "kamiyomu" "services:
  kamiyomu:
    image: marcoscostadev/kamiyomu:latest
    container_name: kamiyomu
    restart: unless-stopped
    healthcheck:
      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:8080/healthz\"]
      interval: 30s
      timeout: 10s
      retries: 3
    ports:
      - \"\${BIND_ADDR}\${PORT}:8080\"
    volumes:
      - \${DATA_PATH}/db:/db
      - \${DATA_PATH}/agents:/agents
      - \${DATA_PATH}/logs:/logs
      - /etc/localtime:/etc/localtime:ro
      - \${MANGA_PATH}:/manga
    networks:
      - homelab-net
    labels:
      com.homekase.service: kamiyomu
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.storage: \"\${MANGA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "kamiyomu" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MANGA_PATH=${MANGA_PATH}
TS=${TS}
KAMIYOMU_URL=${KAMIYOMU_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}/db" "${DATA_PATH}/agents" "${DATA_PATH}/logs" "${MANGA_PATH}"
}

remove_kamiyomu() {
  require_root
  header "Removing KamiYomu"
  local port
  port="$(config_app_get kamiyomu port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "kamiyomu"
  config_app_remove kamiyomu
  ok "KamiYomu removed."
}
