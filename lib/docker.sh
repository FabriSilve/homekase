#!/bin/bash

install_docker() {
  info "Docker is required for all services. Installing Docker Engine + Compose."

  if is_installed docker; then
    info "Docker already installed, skipping"
    return
  fi

  info "Installing Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt update -qq
  apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker "$(get_user)"
  ok "Docker installed"
}

create_homelab_dirs() {
  mkdir -p "$HOMELAB_DIR"/{traefik,monitoring,apps}
  chown -R "$(get_user):$(get_user)" "$HOMELAB_DIR" 2>/dev/null || true
}
