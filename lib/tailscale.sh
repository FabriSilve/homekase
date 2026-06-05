#!/bin/bash

setup_tailscale() {
  section "Tailscale (Optional)" \
    "Tailscale creates a secure WireGuard mesh between your devices.
No ports need to be opened on your router — your phone, laptop, and server
can all communicate securely over the internet as if they were on the same LAN."

  if ! prompt_yes_no "Install and set up Tailscale?" "n"; then
    info "Tailscale skipped"
    return
  fi

  if is_installed tailscale && tailscale status 2>/dev/null | grep -q "Logged in"; then
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    ok "Tailscale already connected${ts_ip:+ ($ts_ip)}"
    return
  fi

  if ! is_installed tailscale; then
    info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale installed"
  fi

  info "Starting Tailscale..."
  echo ""
  echo -e "  ${BOLD}Open the following URL in your browser (phone or laptop):${NC}"
  echo ""

  tailscale up --accept-dns=false --accept-routes=false

  echo ""

  local ts_ip
  ts_ip=$(tailscale ip -4 2>/dev/null || true)
  if [ -z "$ts_ip" ]; then
    warn "Tailscale installed but not connected — run 'sudo tailscale up' manually"
    return
  fi

  ok "Tailscale connected! Your server's Tailscale IP: ${BOLD}$ts_ip${NC}"
  echo ""

  if prompt_yes_no "Can you configure custom DNS on your router?" "n"; then
    router_dns_config "$ts_ip"
  else
    tailscale_dns_config "$ts_ip"
  fi
}

router_dns_config() {
  local ts_ip="$1"
  echo -e "  ${BOLD}LAN access (all devices):${NC}"
  echo -e "  Configure your router's DHCP to announce the server's"
  echo -e "  LAN IP as DNS. Then all devices resolve ${CYAN}.home${NC} URLs."
  echo ""
  echo -e "  ${BOLD}Remote access (Tailscale):${NC}"
  echo -e "  http://${ts_ip}:8090   — Beszel monitoring"
  echo ""
}

tailscale_dns_config() {
  local ts_ip="$1"
  local lan_ip
  lan_ip=$(hostname -I | awk '{print $1}')

  warn "Your router does not support custom DNS — using Tailscale DNS routes instead."
  echo ""
  echo -e "  ${BOLD}Step 1: Configure Tailscale DNS routes${NC}"
  echo -e "  Go to:  ${CYAN}https://login.tailscale.com/admin/dns${NC}"
  echo -e "  Under ${BOLD}Nameservers${NC}, add: ${ts_ip}"
  echo -e "  Restrict to domain: ${BOLD}home${NC}"
  echo ""
  echo -e "  ${BOLD}Step 2 (Tailscale devices):${NC}"
  echo -e "  Enable ${BOLD}Use Tailscale DNS${NC} in the client settings."
  echo -e "  Then ${CYAN}.home${NC} URLs resolve through Tailscale."
  echo ""
  echo -e "  ${BOLD}Step 3 (LAN devices without Tailscale):${NC}"
  echo -e "  Edit ${BOLD}/etc/hosts${NC} on your laptop (use LAN IP, not Tailscale IP):"
  echo -e "  ${lan_ip}  monitoring.home dns.home jellyfin.home photos.home"
  echo -e "  ${lan_ip}  torrent.home sync.home"
  echo ""
  echo -e "  ${BOLD}Remote access (Tailscale):${NC}"
  echo -e "  http://${ts_ip}:8090   — Beszel monitoring"
  echo ""
}
