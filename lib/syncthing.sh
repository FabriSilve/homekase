#!/bin/bash

deploy_syncthing() {
  header "Syncthing"

  if docker compose ls | grep -q syncthing; then
    info "Syncthing already running, skipping"
    return
  fi

  mkdir -p "$DATA_DIR/config/syncthing"

  mkdir -p "$HOMELAB_DIR/syncthing"

  cat > "$HOMELAB_DIR/syncthing/docker-compose.yml" << SYNCTHING
services:
  syncthing:
    image: syncthing/syncthing:1.27
    container_name: syncthing
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /data/config/syncthing:/var/syncthing/config
      - ${STORAGE_DIR:-$DATA_DIR}:/var/syncthing/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.syncthing.rule=Host(\`sync.home\`)"
      - "traefik.http.routers.syncthing.entrypoints=web"
      - "traefik.http.services.syncthing.loadbalancer.server.port=8384"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
SYNCTHING

  docker compose -f "$HOMELAB_DIR/syncthing/docker-compose.yml" up -d

  append_url "Syncthing     → http://sync.home"

  ok "Syncthing deployed at http://sync.home"
}
