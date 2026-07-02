#!/usr/bin/env bash

cmd_server_docker() {
  require_root
  header "Docker Engine Installation"

  if is_installed docker; then
    ok "Docker already installed."
    docker --version
  else
    info "Installing Docker Engine via official apt repository..."

    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    # shellcheck disable=SC2312
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    local arch distro
    arch="$(dpkg --print-architecture)"
    # shellcheck disable=SC2154
    distro="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
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
    usermod -aG docker "${target_user}"
    usermod -aG docker root
    ok "User '${target_user}' added to docker group."

    docker network create homelab-net 2>/dev/null || true
    ok "Docker network 'homelab-net' ready."

    ok "Docker installed. Log out and back in for group membership to take effect."
  fi

  # lazydocker TUI — installed idempotently regardless of Docker install path
  header "lazydocker Installation"
  if is_installed lazydocker; then
    ok "lazydocker already installed."
    lazydocker --version
  else
    info "Installing lazydocker..."
    local lazy_arch lazy_tag lazy_file lazy_url
    lazy_arch="$(uname -m)"
    case "${lazy_arch}" in
      i386|i686) lazy_arch=x86 ;;
      armv6*)    lazy_arch=armv6 ;;
      armv7*)    lazy_arch=armv7 ;;
      aarch64*)  lazy_arch=arm64 ;;
    esac
    lazy_tag="$(curl -sL -H 'Accept: application/json' \
      https://github.com/jesseduffield/lazydocker/releases/latest \
      | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/')"
    lazy_file="lazydocker_${lazy_tag//v/}_$(uname -s)_${lazy_arch}.tar.gz"
    lazy_url="https://github.com/jesseduffield/lazydocker/releases/download/${lazy_tag}/${lazy_file}"
    curl -sL -o /tmp/lazydocker.tar.gz "${lazy_url}"
    tar -xzf /tmp/lazydocker.tar.gz -C /tmp lazydocker
    install -Dm 755 /tmp/lazydocker /usr/local/bin/lazydocker
    rm -f /tmp/lazydocker /tmp/lazydocker.tar.gz
    ok "lazydocker installed."
  fi
}
