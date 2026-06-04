#!/bin/bash

deploy_beszel() {
  header "Beszel (Monitoring)"

  if docker compose ls | grep -q beszel; then
    info "Beszel already running, skipping"
    return
  fi

  mkdir -p "$DATA_DIR/config/beszel"

  mkdir -p "$HOMELAB_DIR/monitoring"

  cat > "$HOMELAB_DIR/monitoring/docker-compose.yml" << BESZEL
services:
  beszel-hub:
    image: henrygd/beszel:0.7
    container_name: beszel
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - /data/config/beszel:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.beszel.rule=Host(\`monitoring.home\`)"
      - "traefik.http.routers.beszel.entrypoints=web"
      - "traefik.http.services.beszel.loadbalancer.server.port=8090"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
BESZEL

  docker compose -f "$HOMELAB_DIR/monitoring/docker-compose.yml" up -d

  append_url "Monitoring    → http://monitoring.home"

  ok "Beszel deployed at http://monitoring.home"
}
