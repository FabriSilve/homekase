#!/bin/bash

set_fish_default() {
  header "Shell Configuration"

  local user
  user=$(get_user)
  local user_home
  user_home=$(get_home)

  # Set fish as default shell (idempotent — skips if already set)
  if grep -q "^$user.*fish$" /etc/passwd; then
    info "Fish is already default shell for $user"
  else
    info "Setting fish as default shell for $user..."
    chsh -s "$(command -v fish)" "$user"
    ok "Default shell set to fish"
  fi

  # Write config to conf.d (idempotent — uses > not >>)
  local conf_d="$user_home/.config/fish/conf.d"
  mkdir -p "$conf_d"

  cat > "$conf_d/homekase.fish" << 'FISH_CONFIG'
# Managed by homekase — do not edit manually

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

  chown -R "$user:$user" "$conf_d" 2>/dev/null || true
  ok "Fish config installed (conf.d/homekase.fish)"
}
