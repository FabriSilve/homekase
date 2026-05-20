#!/bin/bash

deploy_qbittorrent() {
  header "qBittorrent + VPN"

  if docker compose ls | grep -q qbittorrent; then
    info "qBittorrent already running, skipping"
    return
  fi

  if ! prompt_yes_no "  Do you want VPN protection with Gluetun?"; then
    deploy_qbittorrent_no_vpn
    return
  fi

  local torrents_path="${STORAGE_DIR:-$DATA_DIR}/torrents"
  mkdir -p "$torrents_path"/{complete,incomplete}
  mkdir -p "$DATA_DIR/config/qbittorrent"

  info "VPN setup required"
  info "Get your WireGuard keys from your VPN provider (e.g., Mullvad)"
  local vpn_provider
  vpn_provider=$(prompt_input "  VPN provider" "mullvad")
  local wg_private_key
  wg_private_key=$(prompt_secret "  WireGuard private key")
  local wg_address
  wg_address=$(prompt_input "  WireGuard address" "")

  mkdir -p "$HOMELAB_DIR/qbittorrent"

  # Write secrets to .env file
  cat > "$HOMELAB_DIR/qbittorrent/.env" << ENV
VPN_SERVICE_PROVIDER=${vpn_provider}
WIREGUARD_PRIVATE_KEY=${wg_private_key}
WIREGUARD_ADDRESSES=${wg_address}
TORRENTS_PATH=${torrents_path}
ENV

  cat > "$HOMELAB_DIR/qbittorrent/docker-compose.yml" << 'QBITTORRENT'
services:
  gluetun:
    image: qmcgaw/gluetun:v3.39
    container_name: gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    env_file:
      - .env
    environment:
      - VPN_TYPE=wireguard
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.qbittorrent.rule=Host(`torrent.home`)"
      - "traefik.http.routers.qbittorrent.entrypoints=web"
      - "traefik.http.services.qbittorrent.loadbalancer.server.port=8080"
    networks:
      - traefik-net

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:4.6.7
    container_name: qbittorrent
    restart: unless-stopped
    network_mode: service:gluetun
    environment:
      - PUID=1000
      - PGID=1000
      - WEBUI_PORT=8080
    volumes:
      - /data/config/qbittorrent:/config
      - ${TORRENTS_PATH}:/data/torrents
    depends_on:
      - gluetun

networks:
  traefik-net:
    external: true
QBITTORRENT

  docker compose -f "$HOMELAB_DIR/qbittorrent/docker-compose.yml" up -d

  append_url "qBittorrent   → http://torrent.home"

  ok "qBittorrent deployed at http://torrent.home"
  info "Default login: admin / adminadmin — change it immediately"
  info "VPN credentials saved to $HOMELAB_DIR/qbittorrent/.env"
}

deploy_qbittorrent_no_vpn() {
  local torrents_path="${STORAGE_DIR:-$DATA_DIR}/torrents"
  mkdir -p "$torrents_path"/{complete,incomplete}
  mkdir -p "$DATA_DIR/config/qbittorrent"

  mkdir -p "$HOMELAB_DIR/qbittorrent"

  # Write paths to .env file
  cat > "$HOMELAB_DIR/qbittorrent/.env" << ENV
TORRENTS_PATH=${torrents_path}
ENV

  cat > "$HOMELAB_DIR/qbittorrent/docker-compose.yml" << 'QBITTORRENT'
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:4.6.7
    container_name: qbittorrent
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - WEBUI_PORT=8080
    volumes:
      - /data/config/qbittorrent:/config
      - ${TORRENTS_PATH}:/data/torrents
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.qbittorrent.rule=Host(`torrent.home`)"
      - "traefik.http.routers.qbittorrent.entrypoints=web"
      - "traefik.http.services.qbittorrent.loadbalancer.server.port=8080"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
QBITTORRENT

  docker compose -f "$HOMELAB_DIR/qbittorrent/docker-compose.yml" up -d

  append_url "qBittorrent   → http://torrent.home (no VPN)"

  ok "qBittorrent deployed at http://torrent.home (no VPN)"
}
