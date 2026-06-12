#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  for cmd in apt-get install gpg systemctl usermod; do
    cat > "$MOCK_DIR/$cmd" <<MOCK
#!/usr/bin/env bash
echo "$cmd \$*"
exit 0
MOCK
    chmod +x "$MOCK_DIR/$cmd"
  done

  cat > "$MOCK_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
echo "fake gpg key data"
exit 0
MOCK
  chmod +x "$MOCK_DIR/curl"

  cat > "$MOCK_DIR/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "Docker version 24.0.0"
  exit 0
fi
if [[ "$1 $2" == "network create" ]]; then
  echo "homelab-net"
  exit 0
fi
exit 0
MOCK
  chmod +x "$MOCK_DIR/docker"

  # dpkg and lsb_release for arch/distro detection
  cat > "$MOCK_DIR/dpkg" <<'MOCK'
#!/usr/bin/env bash
echo "amd64"
exit 0
MOCK
  chmod +x "$MOCK_DIR/dpkg"

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  require_root() { return 0; }
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "cmd_server_docker skips install when docker already present" {
  # docker mock exits 0 for --version, so is_installed returns true
  source "$PROJECT_ROOT/lib/server/docker.sh"
  run cmd_server_docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker already installed"* ]]
}

@test "cmd_server_docker shows Docker Engine Installation header" {
  source "$PROJECT_ROOT/lib/server/docker.sh"
  run cmd_server_docker
  [[ "$output" == *"Docker Engine Installation"* ]]
}
