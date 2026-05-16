#!/bin/bash

deploy_jellyfin() {
  header "Jellyfin"

  if docker compose ls | grep -q jellyfin; then
    info "Jellyfin already running, skipping"
    return
  fi

  local media_path="${STORAGE_DIR:-$DATA_DIR}/media"
  mkdir -p "$media_path"
  mkdir -p "$DATA_DIR/config/jellyfin"

  mkdir -p "$HOMELAB_DIR/jellyfin"

  cat > "$HOMELAB_DIR/jellyfin/docker-compose.yml" << JELLYFIN
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "8096:8096"
    volumes:
      - /data/config/jellyfin:/config
      - ${media_path}:/media:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jellyfin.rule=Host(\`jellyfin.home\`)"
      - "traefik.http.routers.jellyfin.entrypoints=web"
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
JELLYFIN

  docker compose -f "$HOMELAB_DIR/jellyfin/docker-compose.yml" up -d

  cat >> "$HOMELAB_DIR/urls.txt" << URLS
Jellyfin      → http://jellyfin.home
URLS

  ok "Jellyfin deployed at http://jellyfin.home"
}
