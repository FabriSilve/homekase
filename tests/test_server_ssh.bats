#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  FAKE_SSHD_CONFIG="$(mktemp)"
  export FAKE_SSHD_CONFIG
  cat > "$FAKE_SSHD_CONFIG" <<'EOF'
#PermitRootLogin yes
#PasswordAuthentication yes
#ChallengeResponseAuthentication yes
EOF

  cat > "$MOCK_DIR/apt-get" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "$MOCK_DIR/apt-get"

  cat > "$MOCK_DIR/systemctl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "$MOCK_DIR/systemctl"

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  require_root() { return 0; }
  ask_confirm() { return 1; }  # skip fail2ban by default

  source "$PROJECT_ROOT/lib/server/ssh.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
  rm -f "$FAKE_SSHD_CONFIG"
}

@test "cmd_server_ssh exits 0" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    require_root() { return 0; }
    ask_confirm() { return 1; }
    source '$PROJECT_ROOT/lib/server/ssh.sh'
    cfg='$FAKE_SSHD_CONFIG'
    _sshd_set() {
      local key=\"\$1\" value=\"\$2\"
      if grep -qE \"^#?\${key}[[:space:]]\" \"\$cfg\"; then
        sed -i '' \"s|^#\\?\${key}[[:space:]].*|\${key} \${value}|\" \"\$cfg\"
      else
        echo \"\${key} \${value}\" >> \"\$cfg\"
      fi
    }
    systemctl() { return 0; }
    export -f systemctl
    cmd_server_ssh
  "
  [ "$status" -eq 0 ]
}

@test "cmd_server_ssh shows SSH Hardening header" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    require_root() { return 0; }
    ask_confirm() { return 1; }
    source '$PROJECT_ROOT/lib/server/ssh.sh'
    cfg='$FAKE_SSHD_CONFIG'
    _sshd_set() { :; }
    systemctl() { return 0; }
    export -f systemctl
    cmd_server_ssh
  "
  [[ "$output" == *"SSH Hardening"* ]]
}
