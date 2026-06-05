#!/bin/bash
# Wrap in function to prevent partial-download execution via curl | bash.
# Bash won't execute until the closing brace is received.
_homekase_bootstrap() {
set -euo pipefail

# Must run as root — check early for clear feedback
if [ "$(whoami)" != "root" ]; then
  echo "This script must be run as root."
  echo "Try: curl -fsSL https://raw.githubusercontent.com/FabriSilve/homekase/master/setup.sh | sudo bash"
  exit 1
fi

# If running via curl | bash, BASH_SOURCE is unset - clone repo and re-exec
if [ -z "${BASH_SOURCE[0]:-}" ] || [ ! -d "$(dirname "${BASH_SOURCE[0]}")/lib" ]; then
  echo ":: Downloading homekase..."
  apt update -qq && apt install -y -qq git
  TEMP_DIR=$(mktemp -d)
  git clone --depth=1 "https://github.com/FabriSilve/homekase.git" "$TEMP_DIR" || {
    echo "Failed to clone repository"
    rm -rf "$TEMP_DIR"
    exit 1
  }
  exec bash "$TEMP_DIR/setup.sh" "$@" </dev/tty
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source config first — other libs depend on it
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/config.sh"

for lib in "$SCRIPT_DIR"/lib/*.sh; do
  # common_wizard.sh is sourced on-demand by setup_wizard_ui()
  [[ "$(basename "$lib")" == "common_wizard.sh" ]] && continue
  # shellcheck disable=SC1090
  source "$lib"
done

DRY_RUN=false
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ] || [ "$arg" = "--check" ]; then
    DRY_RUN=true
  fi
done

if $DRY_RUN; then
  # Override destructive commands in dry-run mode
  apt() { echo -e "${YELLOW}[DRY-RUN]${NC} apt $*"; }
  docker() { echo -e "${YELLOW}[DRY-RUN]${NC} docker $*"; }
  curl() { echo -e "${YELLOW}[DRY-RUN]${NC} curl $*"; }
  git() { echo -e "${YELLOW}[DRY-RUN]${NC} git $*"; }
  pvcreate() { echo -e "${YELLOW}[DRY-RUN]${NC} pvcreate $*"; }
  vgcreate() { echo -e "${YELLOW}[DRY-RUN]${NC} vgcreate $*"; }
  lvcreate() { echo -e "${YELLOW}[DRY-RUN]${NC} lvcreate $*"; }
  mkfs.ext4() { echo -e "${YELLOW}[DRY-RUN]${NC} mkfs.ext4 $*"; }
  mount() { echo -e "${YELLOW}[DRY-RUN]${NC} mount $*"; }
  ufw() { echo -e "${YELLOW}[DRY-RUN]${NC} ufw $*"; }
  chsh() { echo -e "${YELLOW}[DRY-RUN]${NC} chsh $*"; }
  chown() { :; }
  systemctl() { echo -e "${YELLOW}[DRY-RUN]${NC} systemctl $*"; }
  gum() { echo -e "${YELLOW}[DRY-RUN]${NC} gum $*"; }
  gpg() { echo -e "${YELLOW}[DRY-RUN]${NC} gpg $*"; }
  tailscale() { echo -e "${YELLOW}[DRY-RUN]${NC} tailscale $*"; }
fi

main() {
  echo ""
  echo -e "${BOLD}┌─────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│${NC}            ${CYAN}🏠  homekase${NC}                   ${BOLD}│${NC}"
  echo -e "${BOLD}│${NC}     Homelab Setup for Ubuntu 24.04      ${BOLD}│${NC}"
  echo -e "${BOLD}└─────────────────────────────────────────┘${NC}"
  echo ""

  setup_wizard_ui

  section "Welcome" \
    "This setup will: update system packages, install dev tools (editor, git TUI, file manager, shell prompt), configure firewall, set up Docker, configure disk storage, and deploy homelab services (reverse proxy, DNS, media, etc.)."

  preflight_check curl git lsblk findmnt openssl parted || exit 1

  local TOTAL_STEPS=13
  local STEP=0

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: System Update & Base Packages"
  run_system_update
  install_base_packages

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Firewall & SSH"
  configure_firewall
  harden_ssh

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Network Setup"
  setup_static_ip
  setup_tailscale

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Developer Tools"
  install_shell_tools
  install_neovim
  install_starship

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Shell Configuration"
  set_fish_default

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Docker"
  install_docker
  create_homelab_dirs
  docker network create traefik-net 2>/dev/null || true
  ok "traefik-net network ready"

  # Limit container logs to 10MB to prevent disk from filling up
  local docker_daemon="/etc/docker/daemon.json"
  if [ ! -f "$docker_daemon" ] || ! grep -q "max-size" "$docker_daemon" 2>/dev/null; then
    mkdir -p /etc/docker
    cat > "$docker_daemon" << 'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON
    systemctl restart docker
    ok "Docker log limit set (10MB per container)"
  fi

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: DNS & Ad Blocking"
  deploy_adguard

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Disk Setup"
  run_disk_setup
  setup_swap

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Reverse Proxy"
  deploy_traefik

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Services"
  service_menu
  deploy_selected_services

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: AI Assistant"
  deploy_assistant

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Backups"
  deploy_backup_service

  ((++STEP))
  header "Step ${STEP}/${TOTAL_STEPS}: Finishing Up"
  install_homekase_function

  generate_summary
}

install_homekase_function() {
  local user_home
  user_home=$(get_home)
  local func_dir="$user_home/.config/fish/functions"
  mkdir -p "$func_dir"
  cp "$SCRIPT_DIR/functions/homekase.fish" "$func_dir/homekase.fish"
  chown -R "$(get_user):$(get_user)" "$user_home/.config" 2>/dev/null || true

  mkdir -p "$HOMELAB_DIR/templates"
  cp -r "$SCRIPT_DIR/templates/." "$HOMELAB_DIR/templates/"
  chown -R "$(get_user):$(get_user)" "$HOMELAB_DIR/templates" 2>/dev/null || true

  ok "homekase fish function installed"
}

generate_summary() {
  local server_ip
  server_ip=$(hostname -I | awk '{print $1}')

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}         🏠  homekase is ready!${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${CYAN}Server IP:${NC}  $server_ip"
  echo ""

  if [ -f "$HOMELAB_DIR/urls.txt" ]; then
    echo -e "  ${BOLD}Services:${NC}"
    cat "$HOMELAB_DIR/urls.txt"
    echo ""
  fi

  echo -e "  ${BOLD}Custom apps:${NC}  http://<app-name>.home"
  echo ""
  echo -e "  ${BOLD}Management:${NC}"
  echo "  homekase create <name>   → Scaffold a new app"
  echo "  homekase update          → Re-run this setup"
  echo "  homekase status          → Show system status"
  echo ""
  echo -e "  ${YELLOW}Next step:${NC} Log out and back in to start using fish."
  echo ""

  if command -v tailscale >/dev/null 2>&1; then
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$ts_ip" ]; then
      echo -e "  ${CYAN}Remote access (Tailscale):${NC}  http://${ts_ip}:8090"
    fi
  fi

  if [ -f "$HOMELAB_DIR/urls.txt" ]; then
    echo -e "  ${YELLOW}DNS setup:${NC} Configure your router's DHCP"
    echo "  to use $server_ip as DNS server for *.home resolution."
    echo "  Or configure each device's /etc/hosts."
  fi
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

main "$@"
}
_homekase_bootstrap "$@"
