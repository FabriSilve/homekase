#!/usr/bin/env bash

cmd_server_docker() {
  require_root
  header "Docker Engine Installation"

  if is_installed docker; then
    ok "Docker already installed."
    docker --version
    return 0
  fi

  info "Installing Docker Engine via official apt repository..."

  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  local arch distro
  arch="$(dpkg --print-architecture)"
  distro="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo \
    "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${distro} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  ok "Docker packages installed."

  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  ok "Docker daemon.json configured (log rotation: 10m × 3 files)."

  systemctl enable --now docker

  local target_user="${SUDO_USER:-$(id -un)}"
  usermod -aG docker "$target_user"
  usermod -aG docker root
  ok "User '$target_user' added to docker group."

  docker network create homelab-net 2>/dev/null || true
  ok "Docker network 'homelab-net' ready."

  ok "Docker installed. Log out and back in for group membership to take effect."
}
