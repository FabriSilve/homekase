#!/usr/bin/env bash

cmd_server_vpn() {
  require_root
  header "Tailscale VPN"

  if ! is_installed tailscale; then
    if ask_confirm "Tailscale not installed. Install now?"; then
      info "Installing Tailscale..."
      # shellcheck disable=SC2312
      curl -fsSL https://tailscale.com/install.sh | sh
      ok "Tailscale installed."
    else
      info "Cancelled."
      return 0
    fi
  else
    ok "Tailscale already installed."
  fi

  # --accept-dns enables MagicDNS: this machine gets a stable DNS name like
  # <hostname>.<tailnet>.ts.net, reachable from any device on the tailnet.
  # That name is what 'tailscale serve' uses when exposing service ports over HTTPS.
  info "Bringing Tailscale up (MagicDNS enabled)..."
  tailscale up --accept-dns

  info "Reading Tailscale status..."
  local ts_json fqdn hostname domain
  ts_json="$(tailscale status --json)"
  fqdn="$(echo "${ts_json}" | yq '.Self.DNSName' -)"
  fqdn="${fqdn%.}"        # strip trailing dot
  hostname="${fqdn%%.*}"  # e.g. "myserver"
  domain="${fqdn#*.}"     # e.g. "tail1234.ts.net"

  config_set 'tailscale.installed' 'true'
  config_set 'tailscale.hostname'  "${fqdn}"
  config_set 'tailscale.domain'    "${domain}"
  ok "Config updated: tailscale.hostname=${fqdn}"

  local ufw_enabled
  ufw_enabled="$(config_get 'ufw.enabled')"
  if [[ "${ufw_enabled}" == "true" ]]; then
    info "UFW enabled — adding tailscale0 allow rule..."
    ufw allow in on tailscale0
    ok "UFW rule added for tailscale0."
  fi

  ok "Tailscale ready."
  info "  MagicDNS hostname : ${fqdn}"
  info "  Tailnet domain    : ${domain}"
  info ""
  info "  Services added via 'homekase add' will offer Tailscale Serve (HTTPS)."
  info "  Each service port becomes reachable at https://${fqdn}:<port> on your tailnet."
  info "  Run 'tailscale serve status' to review active routes."
}
