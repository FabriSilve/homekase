#!/usr/bin/env bash

cmd_server_swap() {
  require_root
  header "Swap File Setup"

  if [[ -f /swapfile ]]; then
    warn "/swapfile already exists."
    if ! ask_confirm "Recreate swapfile? (existing swap will be turned off)"; then
      info "Cancelled."
      return 0
    fi
    swapoff /swapfile
    rm -f /swapfile
    info "Existing swapfile removed."
  fi

  info "Creating 6G swapfile..."
  fallocate -l 6G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  ok "Swapfile active."

  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Added /swapfile to /etc/fstab."
  else
    info "/swapfile already in /etc/fstab — skipping."
  fi

  sysctl -w vm.swappiness=10
  if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    ok "vm.swappiness=10 persisted in /etc/sysctl.conf."
  else
    sed -i 's/^vm\.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    ok "vm.swappiness=10 updated in /etc/sysctl.conf."
  fi

  ok "Swap configured: 6G swapfile, swappiness=10."
}
