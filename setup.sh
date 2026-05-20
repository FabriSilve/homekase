#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/FabriSilve/homekase.git"

# Must run as root — check early for clear feedback
if [ "$(whoami)" != "root" ]; then
  echo "This script must be run as root."
  echo "Try: curl -fsSL https://raw.githubusercontent.com/FabriSilve/homekase/main/setup.sh | sudo bash"
  exit 1
fi

# If running via curl | bash, clone the repo first
if [ ! -d "$(dirname "$0")/lib" ]; then
  echo ":: Downloading homekase..."
  apt update -qq && apt install -y -qq git
  TEMP_DIR=$(mktemp -d)
  git clone --depth=1 "$REPO_URL" "$TEMP_DIR" 2>/dev/null || {
    echo "Failed to clone repository"
    exit 1
  }
  cd "$TEMP_DIR"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for lib in "$SCRIPT_DIR"/lib/*.sh; do
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
fi

main() {
  echo ""
  echo -e "${BOLD}┌─────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│${NC}            ${CYAN}🏠  homekase${NC}                   ${BOLD}│${NC}"
  echo -e "${BOLD}│${NC}     Homelab Setup for Ubuntu 24.04      ${BOLD}│${NC}"
  echo -e "${BOLD}└─────────────────────────────────────────┘${NC}"
  echo ""

  setup_wizard_ui

  preflight_check curl git lsblk findmnt openssl || exit 1

  run_system_update
  install_base_packages
  configure_firewall
  install_shell_tools
  install_neovim
  install_starship
  set_fish_default
  install_docker
  create_homelab_dirs
  run_disk_setup
  deploy_traefik
  deploy_adguard
  service_menu
  deploy_selected_services

  # Install the homekase fish function
  install_homekase_function

  # Generate summary
  generate_summary
}

install_homekase_function() {
  local user_home
  user_home=$(get_home)
  local func_dir="$user_home/.config/fish/functions"
  mkdir -p "$func_dir"
  cp "$SCRIPT_DIR/functions/homekase.fish" "$func_dir/homekase.fish"
  chown -R "$(get_user):$(get_user)" "$func_dir" 2>/dev/null || true

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
