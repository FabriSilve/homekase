#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  cat > "$MOCK_DIR/ip" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"-br addr show"* ]]; then
  echo "eth0   UP   192.168.1.10/24"
elif [[ "$*" == *"route"* ]]; then
  echo "default via 192.168.1.1 dev eth0 proto dhcp"
fi
exit 0
MOCK
  chmod +x "$MOCK_DIR/ip"

  # mock grep for /etc/resolv.conf
  cat > "$MOCK_DIR/grep" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"nameserver"* ]]; then
  echo "nameserver 8.8.8.8"
  echo "nameserver 1.1.1.1"
else
  /usr/bin/grep "$@"
fi
exit 0
MOCK
  chmod +x "$MOCK_DIR/grep"

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/server/network.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "cmd_server_network exits 0" {
  run cmd_server_network
  [ "$status" -eq 0 ]
}

@test "cmd_server_network shows Network Interfaces header" {
  run cmd_server_network
  [[ "$output" == *"Network Interfaces"* ]]
}

@test "cmd_server_network shows Default Gateway header" {
  run cmd_server_network
  [[ "$output" == *"Default Gateway"* ]]
}

@test "cmd_server_network shows DNS Nameservers header" {
  run cmd_server_network
  [[ "$output" == *"DNS Nameservers"* ]]
}
