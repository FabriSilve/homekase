#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  FAKE_CONFIG="$(mktemp)"
  export FAKE_CONFIG
  cat > "$FAKE_CONFIG" <<'EOF'
version: "1"
tailscale:
  installed: "false"
ufw:
  enabled: "false"
EOF

  cat > "$MOCK_DIR/tailscale" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "up" ]]; then exit 0; fi
if [[ "$1" == "status" && "$2" == "--json" ]]; then
  echo '{"Self":{"DNSName":"mymachine.tail12345.ts.net."}}'
  exit 0
fi
exit 0
MOCK
  chmod +x "$MOCK_DIR/tailscale"

  REAL_YQ="$(which yq)"
  cat > "$MOCK_DIR/yq" <<MOCK
#!/usr/bin/env bash
if [[ "\$1" == ".Self.DNSName" ]]; then
  cat | grep -o '"DNSName":"[^"]*"' | cut -d'"' -f4
  exit 0
fi
"$REAL_YQ" "\$@"
MOCK
  chmod +x "$MOCK_DIR/yq"

  cat > "$MOCK_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
echo "fake installer"
exit 0
MOCK
  chmod +x "$MOCK_DIR/curl"

  cat > "$MOCK_DIR/sh" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "$MOCK_DIR/sh"

  cat > "$MOCK_DIR/ufw" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "$MOCK_DIR/ufw"

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"
  export HOMEKASE_CONFIG="$FAKE_CONFIG"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  require_root() { return 0; }
  is_installed() {
    [[ "$1" == "tailscale" ]] && return 0
    command -v "$1" &>/dev/null
  }
  ask_confirm() { return 0; }

  source "$PROJECT_ROOT/lib/server/vpn.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
  rm -f "$FAKE_CONFIG"
}

@test "cmd_server_vpn exits 0 when tailscale already installed" {
  run cmd_server_vpn
  [ "$status" -eq 0 ]
}

@test "cmd_server_vpn shows Tailscale VPN header" {
  run cmd_server_vpn
  [[ "$output" == *"Tailscale VPN"* ]]
}

@test "cmd_server_vpn sets tailscale.installed in config" {
  cmd_server_vpn
  result="$(config_get 'tailscale.installed')"
  [ "$result" = "true" ]
}
