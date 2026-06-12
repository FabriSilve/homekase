#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  cat > "$MOCK_DIR/ufw" <<'MOCK'
#!/usr/bin/env bash
echo "ufw $*"
exit 0
MOCK
  chmod +x "$MOCK_DIR/ufw"

  export PATH="$MOCK_DIR:$PATH"

  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/server/firewall.sh"

  # Override require_root — tests run without root; we test firewall logic not auth
  require_root() { return 0; }
}

teardown() {
  rm -rf "$MOCK_DIR"
  rm -f "$HOMEKASE_CONFIG"
}

@test "cmd_server_firewall with no args exits 0 and shows help" {
  run cmd_server_firewall
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"open"* ]]
  [[ "$output" == *"close"* ]]
  [[ "$output" == *"status"* ]]
}

@test "cmd_server_firewall --help exits 0 and shows help" {
  run cmd_server_firewall --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup"* ]]
}

@test "cmd_server_firewall open with no port exits 1" {
  run cmd_server_firewall open
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
}

@test "cmd_server_firewall close with no port exits 1" {
  run cmd_server_firewall close
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
}

@test "cmd_server_firewall open <port> calls ufw allow" {
  run cmd_server_firewall open 8096
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw allow 8096/tcp"* ]]
}

@test "cmd_server_firewall close <port> calls ufw deny" {
  run cmd_server_firewall close 8096
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw deny 8096/tcp"* ]]
}

@test "cmd_server_firewall status calls ufw status verbose" {
  run cmd_server_firewall status
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw status verbose"* ]]
}

@test "cmd_server_firewall unknown subcommand exits 1" {
  run cmd_server_firewall badcmd
  [ "$status" -eq 1 ]
}
