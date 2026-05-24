#!/bin/bash

deploy_traefik() {
  header "Traefik"

  if docker compose ls | grep -q traefik; then
    info "Traefik already running, skipping"
    return
  fi

  mkdir -p "$HOMELAB_DIR/traefik"

  # Generate basic auth credentials for dashboard
  local dash_password
  dash_password=$(openssl rand -base64 12)
  local dash_hash
  dash_hash=$(openssl passwd -apr1 "$dash_password")
  # Double $ signs so Docker Compose doesn't interpolate hash as variables
  local escaped_hash="${dash_hash//\$/\$\$}"
  local auth_label="admin:${escaped_hash}"

  cat > "$HOMELAB_DIR/traefik/.env" << ENV
DASHBOARD_AUTH=${auth_label}
ENV

  # Ask about TLS
  local tls_enabled=false
  if prompt_yes_no "Enable HTTPS with self-signed certificates for LAN?"; then
    tls_enabled=true
    generate_self_signed_cert
  fi

  if [ "$tls_enabled" = true ]; then
    write_traefik_compose_tls
  else
    write_traefik_compose_plain
  fi

  docker compose -f "$HOMELAB_DIR/traefik/docker-compose.yml" up -d

  ok "Traefik deployed at http://dashboard.home"
  info "Dashboard login: admin / $dash_password"
  info "Credentials saved to $HOMELAB_DIR/traefik/.env"
  if [ "$tls_enabled" = true ]; then
    info "Self-signed TLS enabled — browsers will show certificate warning (expected for LAN)"
  fi
}

generate_self_signed_cert() {
  local cert_dir="$HOMELAB_DIR/traefik/certs"
  mkdir -p "$cert_dir"

  if [ -f "$cert_dir/homelab.crt" ] && [ -f "$cert_dir/homelab.key" ]; then
    info "Certificates already exist, reusing"
    return
  fi

  info "Generating self-signed certificate for *.home..."
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "$cert_dir/homelab.key" \
    -out "$cert_dir/homelab.crt" \
    -subj "/CN=*.home" \
    -addext "subjectAltName=DNS:*.home,DNS:home" \
    2>/dev/null
  ok "Self-signed certificate generated (valid 10 years)"
}

write_traefik_compose_tls() {
  # Dynamic config for TLS certificates
  cat > "$HOMELAB_DIR/traefik/dynamic.yml" << 'DYNAMIC'
tls:
  certificates:
    - certFile: /certs/homelab.crt
      keyFile: /certs/homelab.key
  stores:
    default:
      defaultCertificate:
        certFile: /certs/homelab.crt
        keyFile: /certs/homelab.key
DYNAMIC

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
      - "--providers.file.filename=/etc/traefik/dynamic.yml"
      - "--entryPoints.web.address=:80"
      - "--entryPoints.websecure.address=:443"
      - "--entryPoints.web.http.redirections.entrypoint.to=websecure"
      - "--entryPoints.web.http.redirections.entrypoint.scheme=https"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./certs:/certs:ro
      - ./dynamic.yml:/etc/traefik/dynamic.yml:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`dashboard.home`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=dashboard-auth"
      - "traefik.http.middlewares.dashboard-auth.basicauth.users=${DASHBOARD_AUTH}"
    networks:
      - traefik-net

networks:
  traefik-net:
    name: traefik-net
    driver: bridge
TRAEFIK_COMPOSE
}

write_traefik_compose_plain() {
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
      - "traefik.http.routers.dashboard.middlewares=dashboard-auth"
      - "traefik.http.middlewares.dashboard-auth.basicauth.users=${DASHBOARD_AUTH}"
    networks:
      - traefik-net

networks:
  traefik-net:
    name: traefik-net
    driver: bridge
TRAEFIK_COMPOSE
}
