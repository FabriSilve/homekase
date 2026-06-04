#!/bin/bash

install_shell_tools() {
  header "Shell & Terminal Tools"

  # Base packages always installed (fish, fzf, bat, ripgrep needed by system)
  local packages=(fish fzf bat ripgrep unzip btop jq mtr ncdu)
  info "Installing base shell tools..."
  apt install -y -qq "${packages[@]}"
  ok "Base shell tools installed"

  # Terminal multiplexer selection
  if is_installed zellij; then
    ok "Terminal multiplexer: zellij installed"
  else
    local mux_choice
    mux_choice=$(prompt_choose "Which terminal multiplexer do you want?" \
      "zellij — Modern terminal workspace with built-in layouts" \
      "Skip — I'll use tmux or my own")
    if [[ "$mux_choice" == zellij* ]]; then
      info "Installing zellij..."
      local ZELLIJ_VERSION
      ZELLIJ_VERSION=$(curl -s "https://api.github.com/repos/zellij-org/zellij/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -fsSL "https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-x86_64-unknown-linux-musl.tar.gz" -o /tmp/zellij.tar.gz
      tar xzf /tmp/zellij.tar.gz -C /tmp
      mv /tmp/zellij /usr/local/bin/zellij
      ok "zellij installed"
    fi
  fi

  # Git TUI selection
  if is_installed lazygit; then
    ok "Git tool: lazygit installed"
  else
    local git_choice
    git_choice=$(prompt_choose "Which git tool do you want?" \
      "lazygit — Terminal UI for git commands" \
      "Skip — I'll use git CLI or my own tool")
    if [[ "$git_choice" == lazygit* ]]; then
      info "Installing lazygit..."
      local LAZYGIT_VERSION
      LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" -o /tmp/lazygit.tar.gz
      tar xzf /tmp/lazygit.tar.gz -C /tmp
      mv /tmp/lazygit /usr/local/bin/lazygit
      ok "lazygit installed"
    fi
  fi

  # File manager selection
  if is_installed yazi; then
    ok "File manager: yazi installed"
  else
    local fm_choice
    fm_choice=$(prompt_choose "Which terminal file manager do you want?" \
      "yazi — Fast TUI file manager with preview" \
      "Skip — I'll use ls/find or my own")
    if [[ "$fm_choice" == yazi* ]]; then
      info "Installing yazi..."
      local YAZI_VERSION
      YAZI_VERSION=$(curl -s "https://api.github.com/repos/sxyazi/yazi/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -fsSL "https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip
      unzip -q /tmp/yazi.zip -d /tmp
      mv "/tmp/yazi-x86_64-unknown-linux-gnu/yazi" /usr/local/bin/yazi
      ok "yazi installed"
    fi
  fi

  # Docker TUI selection
  if is_installed lazydocker; then
    ok "Docker tool: lazydocker installed"
  else
    local docker_choice
    docker_choice=$(prompt_choose "Which Docker tool do you want?" \
      "lazydocker — Terminal UI for Docker and docker-compose" \
      "Skip — I'll use docker CLI or my own tool")
    if [[ "$docker_choice" == lazydocker* ]]; then
      info "Installing lazydocker..."
      curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
      ok "lazydocker installed"
    fi
  fi

  # GitHub CLI (not optional — needed for runner setup)
  if is_installed gh; then
    info "GitHub CLI already installed"
  else
    info "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd status=none of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt update -qq
    apt install -y -qq gh
    ok "GitHub CLI installed"
  fi
}

install_neovim() {
  # Terminal editor selection
  local editor_choice
  editor_choice=$(prompt_choose "Which terminal editor do you want?" \
    "LazyVim — Neovim with IDE features pre-configured" \
    "Skip — I'll install my own editor")

  if [[ "$editor_choice" == Skip* ]]; then
    info "Editor installation skipped"
    return
  fi

  header "Neovim & LazyVim"

  if is_installed nvim; then
    info "Neovim already installed, skipping"
  else
    info "Installing Neovim..."
    curl -fsSL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz -o /tmp/nvim.tar.gz
    rm -rf /opt/nvim-linux-x86_64
    tar xzf /tmp/nvim.tar.gz -C /opt
    ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    ok "Neovim installed"
  fi

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
  chown -R "$(get_user):$(get_user)" "$user_home/.config" 2>/dev/null || true
  ok "LazyVim installed"
}

install_starship() {
  # Shell prompt selection
  local prompt_choice
  prompt_choice=$(prompt_choose "Which shell prompt do you want?" \
    "Starship — Fast prompt showing git status, language versions, etc." \
    "Skip — I'll configure my own prompt")

  if [[ "$prompt_choice" == Skip* ]]; then
    info "Shell prompt installation skipped"
    return
  fi

  header "Starship Prompt"

  if is_installed starship; then
    info "Starship already installed, skipping"
    return
  fi

  curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  ok "Starship installed"
}
