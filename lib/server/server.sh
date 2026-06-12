#!/usr/bin/env bash

_server_help() {
  echo
  echo -e "${BOLD}homekase server${RESET} — server configuration"
  echo
  echo -e "${BOLD}USAGE${RESET}"
  echo "  homekase server <subcommand>"
  echo
  echo -e "${BOLD}SUBCOMMANDS${RESET}"
  printf "  %-12s %s\n" "ssh"      "Harden SSH: key-only login, fail2ban"
  printf "  %-12s %s\n" "firewall" "Manage UFW rules (setup, open, close, status)"
  printf "  %-12s %s\n" "network"  "Show interfaces, gateway, DNS (read-only)"
  printf "  %-12s %s\n" "vpn"      "Install and connect Tailscale"
  printf "  %-12s %s\n" "swap"     "Create 6G swapfile with swappiness=10"
  printf "  %-12s %s\n" "disk"     "Show block devices, disk usage, volume summaries"
  printf "  %-12s %s\n" "docker"   "Install Docker Engine + Compose + Buildx"
  echo
  echo "  Run 'homekase server <subcommand> --help' for details."
  echo
}

cmd_server() {
  local subcmd="${1:-}"
  [[ "$subcmd" == "--help" || "$subcmd" == "-h" ]] && { _server_help; return 0; }

  if [[ -z "$subcmd" ]]; then
    _server_help
    return 0
  fi

  shift

  case "$subcmd" in
    ssh)      source "$HOMEKASE_DIR/lib/server/ssh.sh";      cmd_server_ssh "$@" ;;
    firewall) source "$HOMEKASE_DIR/lib/server/firewall.sh"; cmd_server_firewall "$@" ;;
    network)  source "$HOMEKASE_DIR/lib/server/network.sh";  cmd_server_network "$@" ;;
    vpn)      source "$HOMEKASE_DIR/lib/server/vpn.sh";      cmd_server_vpn "$@" ;;
    swap)     source "$HOMEKASE_DIR/lib/server/swap.sh";     cmd_server_swap "$@" ;;
    disk)     source "$HOMEKASE_DIR/lib/server/disk.sh";     cmd_server_disk "$@" ;;
    docker)   source "$HOMEKASE_DIR/lib/server/docker.sh";   cmd_server_docker "$@" ;;
    *)
      error "Unknown server subcommand: $subcmd"
      echo
      _server_help
      return 1
      ;;
  esac
}
