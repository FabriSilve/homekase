#!/usr/bin/env bash

cmd_server_vpn() {
  require_root
  header "Tailscale VPN"

  if ! is_installed tailscale; then
    if ask_confirm "Tailscale is not installed. Install now?"; then
      info "Installing Tailscale..."
      curl -fsSL https://tailscale.com/install.sh | sh
      ok "Tailscale installed."
    else
      info "Cancelled."
      return 0
    fi
  else
    ok "Tailscale already installed."
  fi

  info "Bringing Tailscale up..."
  tailscale up

  info "Reading Tailscale hostname..."
  local hostname
  hostname="$(tailscale status --json | yq '.Self.DNSName' -)"
  hostname="${hostname%.}"

  config_set 'tailscale.installed' 'true'
  config_set 'tailscale.hostname' "$hostname"
  ok "Config updated: tailscale.hostname=$hostname"

  if [[ "$(config_get 'ufw.enabled')" == "true" ]]; then
    info "UFW is enabled — adding tailscale0 allow rule..."
    ufw allow in on tailscale0
    ok "UFW rule added for tailscale0."
  fi

  ok "Tailscale ready. Hostname: $hostname"
}
