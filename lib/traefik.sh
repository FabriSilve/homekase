#!/bin/bash

deploy_traefik() {
  header "Traefik"

  if docker compose ls | grep -q traefik; then
    info "Traefik already running, skipping"
    return
  fi

  mkdir -p "$HOMELAB_DIR/traefik"

  cat > "$HOMELAB_DIR/traefik/docker-compose.yml" << 'TRAEFIK_COMPOSE'
services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entryPoints.web.address=:80"
      - "--entryPoints.websecure.address=:443"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`dashboard.home`)"
      - "traefik.http.routers.dashboard.entrypoints=web"
      - "traefik.http.routers.dashboard.service=api@internal"
    networks:
      - traefik-net

networks:
  traefik-net:
    name: traefik-net
    driver: bridge
TRAEFIK_COMPOSE

  docker compose -f "$HOMELAB_DIR/traefik/docker-compose.yml" up -d
  ok "Traefik deployed at http://dashboard.home"
}
