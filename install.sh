#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/homekase"
CONFIG_DIR="/etc/homekase"
SSH_DIR="$CONFIG_DIR/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
REPO_SSH="git@github.com:FabriSilve/homekase.git"
BIN_LINK="/usr/local/bin/homekase"
YQ_VERSION="v4.44.1"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
_info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
_ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
_error() { echo -e "${RED}✗${RESET}  $*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || _error "Run as root: sudo bash install.sh"

# Already installed?
if [[ -d "$INSTALL_DIR" && -x "$BIN_LINK" ]]; then
  _info "homekase already installed at $INSTALL_DIR"
  _info "Run 'homekase update' to pull the latest version."
  exit 0
fi

# Prerequisites: git
if ! command -v git &>/dev/null; then
  _info "Installing git..."
  apt-get update -qq && apt-get install -y -qq git
fi
_ok "git ready"

# Prerequisites: yq
if ! command -v yq &>/dev/null; then
  _info "Installing yq $YQ_VERSION..."
  YQ_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
  wget -qO /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}"
  chmod +x /usr/local/bin/yq
fi
_ok "yq ready"

# SSH key for GitHub
_info "Setting up SSH key for GitHub access..."
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ ! -f "$SSH_KEY" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "homekase@$(hostname)" -q
  chmod 600 "$SSH_KEY"
  chmod 644 "${SSH_KEY}.pub"
  _ok "SSH key generated"
else
  _ok "SSH key already exists"
fi

echo
echo -e "${BOLD}Add this public key to your GitHub account:${RESET}"
echo -e "  ${BOLD}https://github.com/settings/keys${RESET}"
echo
cat "${SSH_KEY}.pub"
echo
read -r -p "Press Enter once the key is added to GitHub... "

# Clone repository
_info "Cloning homekase..."
export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new"
git clone "$REPO_SSH" "$INSTALL_DIR"

# Symlink
chmod +x "$INSTALL_DIR/homekase"
ln -sf "$INSTALL_DIR/homekase" "$BIN_LINK"
_ok "homekase linked to $BIN_LINK"

# Initialize config
if [[ ! -f "$CONFIG_DIR/homekase.yml" ]]; then
  mkdir -p "$CONFIG_DIR"
  cp "$INSTALL_DIR/templates/homekase.yml.template" "$CONFIG_DIR/homekase.yml"
  chmod 644 "$CONFIG_DIR/homekase.yml"
  chown root:root "$CONFIG_DIR/homekase.yml"
fi
yq -i ".ssh_key = \"$SSH_KEY\"" "$CONFIG_DIR/homekase.yml"
_ok "Config at $CONFIG_DIR/homekase.yml"

echo
_ok "homekase installed!"
echo
echo -e "  ${BOLD}homekase --help${RESET}      — available commands"
echo -e "  ${BOLD}homekase init${RESET}        — install CLI tools"
echo -e "  ${BOLD}homekase server${RESET}      — configure this server"
echo -e "  ${BOLD}homekase list${RESET}        — browse available services"
echo
