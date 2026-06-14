#!/usr/bin/env bash
# qBittorrent service installer (with optional Gluetun VPN).
# Sourced by lib/services/service.sh on `homekase add qbittorrent`.

deploy_qbittorrent() {
  require_root
  header "Installing qBittorrent"

  local PORT TORRENTS_PATH USE_VPN TS
  local WG_PRIVATE_KEY WG_SERVER WG_SERVER_PUBKEY

  PORT="$(port_wizard "qbittorrent" 1)"
  TORRENTS_PATH="$(ask_input "Torrents storage path" "/storage/torrents")"
  TS="$(tailscale_serve_setup "${PORT}")"

  if ask_confirm "Route traffic through VPN (Gluetun/WireGuard)?"; then
    USE_VPN="true"
    WG_PRIVATE_KEY="$(ask_input "WireGuard private key" "")"
    WG_SERVER="$(ask_input "WireGuard server address (e.g. vpn.example.com)" "")"
    WG_SERVER_PUBKEY="$(ask_input "WireGuard server public key" "")"
  else
    USE_VPN="false"
    WG_PRIVATE_KEY=""
    WG_SERVER=""
    WG_SERVER_PUBKEY=""
  fi

  write_service_dir "qbittorrent"

  if [[ "${USE_VPN}" == "true" ]]; then
    write_compose_file "qbittorrent" "services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - \"\${PORT}:8080\"
    environment:
      VPN_SERVICE_PROVIDER: custom
      VPN_TYPE: wireguard
      WIREGUARD_PRIVATE_KEY: \${WG_PRIVATE_KEY}
      WIREGUARD_ADDRESSES: 10.64.0.1/32
      VPN_ENDPOINT_IP: \${WG_SERVER}
      WIREGUARD_PUBLIC_KEY: \${WG_SERVER_PUBKEY}
    networks:
      - homelab-net

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    network_mode: service:gluetun
    depends_on:
      - gluetun
    environment:
      PUID: 1000
      PGID: 1000
      WEBUI_PORT: 8080
    volumes:
      - \${TORRENTS_PATH}:/downloads
    labels:
      com.homekase.service: qbittorrent
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: none
      com.homekase.backup.db-type: none

networks:
  homelab-net:
    external: true"
  else
    write_compose_file "qbittorrent" "services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
      WEBUI_PORT: 8080
    ports:
      - \"\${PORT}:8080\"
    volumes:
      - \${TORRENTS_PATH}:/downloads
    networks:
      - homelab-net
    labels:
      com.homekase.service: qbittorrent
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: none
      com.homekase.backup.db-type: none

networks:
  homelab-net:
    external: true"
  fi

  write_env_file "qbittorrent" "PORT=${PORT}
TORRENTS_PATH=${TORRENTS_PATH}
TS=${TS}
USE_VPN=${USE_VPN}
WG_PRIVATE_KEY=${WG_PRIVATE_KEY}
WG_SERVER=${WG_SERVER}
WG_SERVER_PUBKEY=${WG_SERVER_PUBKEY}"

  mkdir -p "${TORRENTS_PATH}"

  start_service "qbittorrent"

  config_app_set qbittorrent installed    true
  config_app_set qbittorrent port         "${PORT}"
  config_app_set qbittorrent storage_path "${TORRENTS_PATH}"
  config_app_set qbittorrent tailscale    "${TS}"

  ok "qBittorrent running on port ${PORT}  →  http://localhost:${PORT}"
}

remove_qbittorrent() {
  require_root
  header "Removing qBittorrent"
  remove_service_dir "qbittorrent"
  config_app_remove qbittorrent
  ok "qBittorrent removed."
}
