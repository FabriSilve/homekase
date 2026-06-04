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

  # Run tailscale up; it prints the auth URL and waits for authentication
  tailscale up --accept-dns=false --accept-routes=false

  echo ""

  local ts_ip
  ts_ip=$(tailscale ip -4 2>/dev/null || true)
  if [ -n "$ts_ip" ]; then
    ok "Tailscale connected! Your server's Tailscale IP: ${BOLD}$ts_ip${NC}"
    echo ""
    echo -e "  ${CYAN}Install Tailscale on your phone/laptop, then access:${NC}"
    echo -e "  http://${ts_ip}:8090   — Beszel monitoring"
    echo -e "  http://${ts_ip}        — Traefik / other services on port 80"
    echo ""
    echo -e "  ${YELLOW}Tip:${NC} Enable MagicDNS in the Tailscale admin console"
    echo -e "  to use hostnames instead of IPs (e.g. http://server:8090)."
  else
    warn "Tailscale installed but not connected — run 'sudo tailscale up' manually"
  fi
}
