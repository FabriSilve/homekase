#!/bin/bash

run_system_update() {
  header "System Update"
  info "Updating package lists..."
  apt update -qq
  info "Upgrading packages..."
  apt upgrade -y -qq
  ok "System is up to date"
}

install_base_packages() {
  header "Base Packages"
  local packages=(
    ca-certificates curl wget git unzip
    software-properties-common gnupg
    ufw
  )
  info "Installing base packages..."
  apt install -y -qq "${packages[@]}"
  ok "Base packages installed"
}

configure_firewall() {
  header "Firewall"
  info "Configuring UFW..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 53/udp
  ufw --force enable
  ok "Firewall configured (SSH, HTTP, HTTPS, DNS)"
}
