#!/bin/bash

set_fish_default() {
  header "Shell Configuration"

  local user
  user=$(get_user)

  if grep -q "^$user.*fish$" /etc/passwd; then
    info "Fish is already default shell for $user, skipping"
    return
  fi

  info "Setting fish as default shell for $user..."
  chsh -s "$(command -v fish)" "$user"
  ok "Default shell set to fish"

  local user_home
  user_home=$(get_home)

  local config_dir="$user_home/.config/fish"
  mkdir -p "$config_dir"

  cat >> "$config_dir/config.fish" << 'FISH_CONFIG'

set -gx EDITOR nvim
set -gx VISUAL nvim

if status is-interactive
    if type -q starship
        starship init fish | source
    end
    if type -q zellij
        alias zj="zellij"
    end
    if type -q yazi
        function y
            yazi $argv
        end
    end
    if type -q lazygit
        alias lg="lazygit"
    end
end
FISH_CONFIG

  chown -R "$user:$user" "$config_dir" 2>/dev/null || true
  ok "Fish config created"
}
