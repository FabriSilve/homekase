#!/usr/bin/env bash
# Immich service installer.
# Sourced by lib/services/service.sh on `homekase add immich`.
# Deploys: immich-server, immich-microservices, immich-machine-learning, postgres, redis.

deploy_immich() {
  require_root
  header "Installing Immich"

  local PORT DATA_PATH PHOTOS_PATH DB_PASSWORD TS IMMICH_URL IMMICH_EXTERNAL_DOMAIN BIND_ADDR

  PORT="$(port_wizard "immich" 1)"
  DATA_PATH="$(ask_input "Postgres data path" "/data/config/immich")"
  PHOTOS_PATH="$(ask_input "Photos upload path" "/storage/photos")"
  DB_PASSWORD="$(openssl rand -base64 16)"
  TS="$(tailscale_serve_setup "${PORT}")"
  IMMICH_URL="$(service_url "${PORT}")"
  IMMICH_EXTERNAL_DOMAIN="${IMMICH_URL#https://}"
  IMMICH_EXTERNAL_DOMAIN="${IMMICH_EXTERNAL_DOMAIN#http://}"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "immich"

  write_compose_file "immich" "services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-server
    restart: unless-stopped
    command: [\"start.sh\", \"immich\"]
    depends_on:
      - redis
      - database
    ports:
      - \"\${BIND_ADDR}\${PORT}:3001\"
    volumes:
      - \${PHOTOS_PATH}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    networks:
      - homelab-net
    labels:
      com.homekase.service: immich
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${PHOTOS_PATH}\"
      com.homekase.backup.db-type: postgres

  immich-microservices:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-microservices
    restart: unless-stopped
    command: [\"start.sh\", \"microservices\"]
    depends_on:
      - redis
      - database
    volumes:
      - \${PHOTOS_PATH}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    networks:
      - homelab-net

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:release
    container_name: immich-machine-learning
    restart: unless-stopped
    volumes:
      - immich-model-cache:/cache
    env_file: .env
    networks:
      - homelab-net

  redis:
    image: redis:6.2-alpine
    container_name: immich-redis
    restart: unless-stopped
    networks:
      - homelab-net

  database:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
    container_name: immich-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: \${DB_PASSWORD}
      POSTGRES_USER: \${DB_USERNAME}
      POSTGRES_DB: \${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - \${DATA_PATH}:/var/lib/postgresql/data
    shm_size: 128mb
    networks:
      - homelab-net

volumes:
  immich-model-cache:

networks:
  homelab-net:
    external: true"

  write_env_file "immich" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
PHOTOS_PATH=${PHOTOS_PATH}
DB_PASSWORD=${DB_PASSWORD}
TS=${TS}
DB_HOSTNAME=database
DB_USERNAME=immich
DB_DATABASE_NAME=immich
REDIS_HOSTNAME=redis
IMMICH_SERVER_URL=http://immich-server:3001
IMMICH__SERVER__EXTERNAL_DOMAIN=${IMMICH_EXTERNAL_DOMAIN}
IMMICH_URL=${IMMICH_URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}" "${PHOTOS_PATH}"

  start_service "immich"

  config_app_set immich installed    true
  config_app_set immich port         "${PORT}"
  config_app_set immich data_path    "${DATA_PATH}"
  config_app_set immich storage_path "${PHOTOS_PATH}"
  config_app_set immich tailscale    "${TS}"

  ok "Immich running on port ${PORT}  →  ${IMMICH_URL}"
}

remove_immich() {
  require_root
  header "Removing Immich"

  local port data_path storage_path
  port="$(config_app_get immich port 2>/dev/null || true)"
  data_path="$(config_app_get immich data_path 2>/dev/null || true)"
  storage_path="$(config_app_get immich storage_path 2>/dev/null || true)"

  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "immich"

  if [[ -n "${data_path}" && -d "${data_path}" ]]; then
    if ask_confirm "Also delete PostgreSQL data at ${data_path}?"; then
      rm -rf "${data_path}"
      ok "Removed ${data_path}"
    else
      info "Database data kept at ${data_path}"
    fi
  fi

  if [[ -n "${storage_path}" && -d "${storage_path}" ]]; then
    if ask_confirm "Also delete photos at ${storage_path}?"; then
      rm -rf "${storage_path}"
      ok "Removed ${storage_path}"
    else
      info "Photos kept at ${storage_path}"
    fi
  fi

  config_app_remove immich
  ok "Immich removed."
}
