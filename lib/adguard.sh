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

  # Pre-seed AdGuard config with admin credentials to avoid open setup wizard race
  local adguard_password
  adguard_password=$(openssl rand -base64 12)
  local adguard_hash
  adguard_hash=$(openssl passwd -6 "$adguard_password")

  if [ ! -f "$DATA_DIR/config/adguard/conf/AdGuardHome.yaml" ]; then
    cat > "$DATA_DIR/config/adguard/conf/AdGuardHome.yaml" << ADGUARD_CONFIG
http:
  address: 0.0.0.0:3000
users:
  - name: admin
    password: ${adguard_hash}
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
ADGUARD_CONFIG
    info "AdGuard admin credentials pre-configured"
  fi

  cat > "$HOMELAB_DIR/traefik/.adguard.env" << ENV
ADGUARD_ADMIN_PASSWORD=${adguard_password}
ENV

  cat > "$HOMELAB_DIR/traefik/adguard.yml" << 'ADGUARD_COMPOSE'
services:
  adguard:
    image: adguard/adguardhome:v0.107.52
    container_name: adguard
    restart: unless-stopped
    # Port 53 is intentionally exposed to all interfaces for LAN DNS resolution.
    # Port 3000 is the initial setup UI — open only during first configuration.
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

  info "AdGuard dashboard: http://$server_ip:3000"
  info "Login: admin / $adguard_password"
  info "Credentials saved to $HOMELAB_DIR/traefik/.adguard.env"
  info "Configure your router's DHCP to use $server_ip as DNS server"

  append_url "AdGuard Home  → http://dns.home"

  ok "AdGuard Home deployed"
}
