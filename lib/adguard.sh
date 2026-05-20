#!/bin/bash

deploy_adguard() {
  section "AdGuard Home" \
    "AdGuard Home is a DNS server that blocks ads and enables *.home domain routing. It will listen on port 53 (DNS) and 3000 (setup UI)."

  if docker compose ls | grep -q adguard; then
    info "AdGuard Home already running, skipping"
    return
  fi

  if ! prompt_yes_no "Deploy AdGuard Home?"; then
    warn "AdGuard Home skipped"
    return
  fi

  mkdir -p "$DATA_DIR/config/adguard/work"
  mkdir -p "$DATA_DIR/config/adguard/conf"

  cat > "$HOMELAB_DIR/traefik/adguard.yml" << 'ADGUARD_COMPOSE'
services:
  adguard:
    image: adguard/adguardhome:v0.107.52
    container_name: adguard
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "784:784/udp"
      - "853:853/tcp"
      - "3000:3000/tcp"
    volumes:
      - /data/config/adguard/work:/opt/adguardhome/work
      - /data/config/adguard/conf:/opt/adguardhome/conf
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.adguard.rule=Host(`dns.home`)"
      - "traefik.http.routers.adguard.entrypoints=web"
      - "traefik.http.services.adguard.loadbalancer.server.port=3000"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
ADGUARD_COMPOSE

  docker compose -f "$HOMELAB_DIR/traefik/adguard.yml" up -d

  local server_ip
  server_ip=$(hostname -I | awk '{print $1}')

  info "Complete AdGuard setup at http://$server_ip:3000"
  info "After setup, configure your router's DHCP to use $server_ip as DNS server"
  info "or set up AdGuard as DHCP server"

  append_url "AdGuard Home  → http://dns.home"

  ok "AdGuard Home deployed"
}
