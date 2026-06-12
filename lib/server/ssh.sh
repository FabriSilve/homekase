#!/usr/bin/env bash

cmd_server_ssh() {
  require_root
  header "SSH Hardening"

  warn "This will make the following changes:"
  warn "  • Set PermitRootLogin no in /etc/ssh/sshd_config"
  warn "  • Set PasswordAuthentication no in /etc/ssh/sshd_config"
  warn "  • Set ChallengeResponseAuthentication no in /etc/ssh/sshd_config"
  warn "  • Restart the ssh service"
  echo

  if ask_confirm "Install fail2ban to block brute-force SSH attempts?"; then
    info "Installing fail2ban..."
    apt-get install -y fail2ban

    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.conf <<'EOF'
[sshd]
enabled  = true
maxretry = 5
bantime  = 3600
findtime = 600
EOF
    systemctl enable --now fail2ban
    ok "fail2ban installed and configured."
  fi

  info "Hardening /etc/ssh/sshd_config..."

  local cfg="/etc/ssh/sshd_config"

  _sshd_set() {
    local key="$1" value="$2"
    if grep -qE "^#?${key}[[:space:]]" "${cfg}"; then
      sed -i "s|^#\?${key}[[:space:]].*|${key} ${value}|" "${cfg}"
    else
      echo "${key} ${value}" >> "${cfg}"
    fi
  }

  _sshd_set "PermitRootLogin"                "no"
  _sshd_set "PasswordAuthentication"         "no"
  _sshd_set "ChallengeResponseAuthentication" "no"

  systemctl restart ssh
  ok "SSH hardened."
}
