#!/bin/bash

install_gum() {
  info "Adding Charm repository..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    | tee /etc/apt/sources.list.d/charm.list > /dev/null
  apt update -qq
  apt install -y -qq gum
  ok "gum installed"
}

setup_wizard_ui() {
  if is_installed gum; then
    if prompt_yes_no "Enable enhanced wizard UI?"; then
      source "$(dirname "${BASH_SOURCE[0]}")/common_wizard.sh"
      ok "Enhanced wizard UI enabled"
      return
    fi
  else
    if prompt_yes_no "Enable enhanced wizard UI? (installs gum)"; then
      install_gum
      source "$(dirname "${BASH_SOURCE[0]}")/common_wizard.sh"
      ok "Enhanced wizard UI enabled"
      return
    fi
  fi
  info "Using standard UI"
}
