#!/bin/bash

install_shell_tools() {
  header "Shell & Terminal Tools"

  local packages=(fish zellij fzf bat ripgrep unzip)

  info "Installing shell tools..."
  apt install -y -qq "${packages[@]}"
  ok "Shell tools installed"

  info "Installing lazygit..."
  local LAZYGIT_VERSION
  LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" -o /tmp/lazygit.tar.gz
  tar xzf /tmp/lazygit.tar.gz -C /tmp
  mv /tmp/lazygit /usr/local/bin/lazygit
  ok "lazygit installed"

  info "Installing yazi..."
  local YAZI_VERSION
  YAZI_VERSION=$(curl -s "https://api.github.com/repos/sxyazi/yazi/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  curl -fsSL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip
  unzip -q /tmp/yazi.zip -d /tmp
  mv "/tmp/yazi-x86_64-unknown-linux-gnu/yazi" /usr/local/bin/yazi
  ok "yazi installed"

  info "Installing GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd status=none of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  apt update -qq
  apt install -y -qq gh
  ok "GitHub CLI installed"
}

install_neovim() {
  header "Neovim & LazyVim"

  info "Installing Neovim..."
  curl -fsSL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz -o /tmp/nvim.tar.gz
  rm -rf /opt/nvim-linux-x86_64
  tar xzf /tmp/nvim.tar.gz -C /opt
  ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
  ok "Neovim installed"

  local user_home
  user_home=$(get_home)
  local nvim_config="$user_home/.config/nvim"

  if dir_exists "$nvim_config"; then
    info "LazyVim config already exists at $nvim_config, skipping"
    return
  fi

  info "Installing LazyVim..."
  git clone --depth=1 https://github.com/LazyVim/starter "$nvim_config" 2>/dev/null || true
  rm -rf "$nvim_config/.git"
  chown -R "$(get_user):$(get_user)" "$nvim_config" 2>/dev/null || true
  ok "LazyVim installed"
}

install_starship() {
  header "Starship Prompt"

  if is_installed starship; then
    info "Starship already installed, skipping"
    return
  fi

  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  ok "Starship installed"
}
