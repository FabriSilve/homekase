#!/usr/bin/env bash
# shellcheck disable=SC2154  # BOLD/RESET set by sourcing script

_firewall_help() {
  echo
  echo -e "${BOLD}homekase server firewall${RESET} — UFW management"
  echo
  echo -e "${BOLD}USAGE${RESET}"
  echo "  homekase server firewall <subcommand> [args]"
  echo
  echo -e "${BOLD}SUBCOMMANDS${RESET}"
  printf "  %-22s %s\n" "setup"        "Default deny-in policy, allow SSH, enable UFW"
  printf "  %-22s %s\n" "open <port>"  "Allow TCP traffic on <port>"
  printf "  %-22s %s\n" "close <port>" "Deny TCP traffic on <port>"
  printf "  %-22s %s\n" "status"       "Show current UFW rules (verbose)"
  echo
}

cmd_server_firewall() {
  local subcmd="${1:-}"
  [[ "${subcmd}" == "--help" || "${subcmd}" == "-h" ]] && { _firewall_help; return 0; }

  if [[ -z "${subcmd}" ]]; then
    _firewall_help
    return 0
  fi

  shift

  case "${subcmd}" in
    setup)
      require_root
      header "UFW firewall setup"
      ufw default deny incoming
      ufw default allow outgoing
      ufw allow 22/tcp comment 'SSH'
      local ts_installed
      ts_installed="$(config_get 'tailscale.installed')"
      if [[ "${ts_installed}" == "true" ]]; then
        ufw allow in on tailscale0
        info "Tailscale interface rule added (tailscale0)"
      fi
      ufw --force enable
      config_set 'ufw.enabled' 'true'
      ok "Firewall configured and enabled."
      ;;
    open)
      local port="${1:-}"
      if [[ -z "${port}" ]]; then
        error "Usage: homekase server firewall open <port>"
        return 1
      fi
      require_root
      ufw allow "${port}/tcp"
      ok "Port ${port}/tcp opened."
      ;;
    close)
      local port="${1:-}"
      if [[ -z "${port}" ]]; then
        error "Usage: homekase server firewall close <port>"
        return 1
      fi
      require_root
      ufw delete allow "${port}/tcp"
      ok "Port ${port}/tcp closed."
      ;;
    status)
      require_root
      ufw status verbose
      ;;
    *)
      error "Unknown firewall subcommand: ${subcmd}"
      echo
      _firewall_help
      return 1
      ;;
  esac
}
