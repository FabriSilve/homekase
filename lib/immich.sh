#!/bin/bash

deploy_immich() {
  header "Immich"

  if docker compose ls | grep -q immich; then
    info "Immich already running, skipping"
    return
  fi

  local photos_path="${STORAGE_DIR:-$DATA_DIR}/photos"
  mkdir -p "$photos_path"
  mkdir -p "$DATA_DIR/databases/immich"

  local db_password
  db_password=$(prompt_secret "  Set Immich database password")
  if [ -z "$db_password" ]; then
    db_password=$(openssl rand -base64 24)
    info "Auto-generated database password"
  fi

  mkdir -p "$HOMELAB_DIR/immich"

  # Write secrets to .env file
  cat > "$HOMELAB_DIR/immich/.env" << ENV
DB_PASSWORD=${db_password}
PHOTOS_PATH=${photos_path}
ENV

  cat > "$HOMELAB_DIR/immich/docker-compose.yml" << 'IMMICH'
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-server
    restart: unless-stopped
    environment:
      DB_HOSTNAME: immich-db
      DB_USERNAME: postgres
      DB_PASSWORD: ${DB_PASSWORD}
      DB_DATABASE: immich
      REDIS_HOSTNAME: immich-redis
    volumes:
      - ${PHOTOS_PATH}:/usr/src/app/upload
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.immich.rule=Host(`photos.home`)"
      - "traefik.http.routers.immich.entrypoints=web,websecure"
      - "traefik.http.routers.immich.tls=true"
      - "traefik.http.services.immich.loadbalancer.server.port=3001"
    depends_on:
      - immich-db
      - immich-redis
    networks:
      - traefik-net
      - immich-net

  immich-microservices:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-microservices
    restart: unless-stopped
    environment:
      DB_HOSTNAME: immich-db
      DB_USERNAME: postgres
      DB_PASSWORD: ${DB_PASSWORD}
      DB_DATABASE: immich
      REDIS_HOSTNAME: immich-redis
    volumes:
      - ${PHOTOS_PATH}:/usr/src/app/upload
    depends_on:
      - immich-db
      - immich-redis
    networks:
      - immich-net

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:release
    container_name: immich-ml
    restart: unless-stopped
    environment:
      DB_HOSTNAME: immich-db
      DB_USERNAME: postgres
      DB_PASSWORD: ${DB_PASSWORD}
      DB_DATABASE: immich
      REDIS_HOSTNAME: immich-redis
    depends_on:
      - immich-db
      - immich-redis
    networks:
      - immich-net

  immich-db:
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    container_name: immich-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: immich
    volumes:
      - /data/databases/immich:/var/lib/postgresql/data
    networks:
      - immich-net

  immich-redis:
    image: redis:7-alpine
    container_name: immich-redis
    restart: unless-stopped
    networks:
      - immich-net

networks:
  traefik-net:
    external: true
  immich-net:
    driver: bridge
IMMICH

  docker compose -f "$HOMELAB_DIR/immich/docker-compose.yml" up -d

  append_url "Immich        → http://photos.home"

  ok "Immich deployed at http://photos.home"
  info "Database password saved to $HOMELAB_DIR/immich/.env"
}
