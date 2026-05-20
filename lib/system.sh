#!/bin/bash

run_system_update() {
  info "Updating system packages to latest versions."
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
  section "Firewall Configuration" \
    "This configures the firewall to allow only SSH, HTTP, HTTPS, and DNS traffic. All other incoming connections will be blocked."

  # Check if UFW is already active with expected rules
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    local has_ssh has_http has_https has_dns
    has_ssh=$(ufw status | grep -c "22/tcp" || true)
    has_http=$(ufw status | grep -c "80/tcp" || true)
    has_https=$(ufw status | grep -c "443/tcp" || true)
    has_dns=$(ufw status | grep -c "53/udp" || true)

    if [ "$has_ssh" -ge 1 ] && [ "$has_http" -ge 1 ] && [ "$has_https" -ge 1 ] && [ "$has_dns" -ge 1 ]; then
      ok "Firewall already configured correctly"
      return
    fi
  fi

  info "Ports to open: SSH (22), HTTP (80), HTTPS (443), DNS (53/udp)"
  if ! prompt_yes_no "Apply firewall rules?"; then
    warn "Firewall configuration skipped"
    return
  fi

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
