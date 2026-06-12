#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"

  FAKE_BIN="$(mktemp -d)"
  SAVED_PATH="$PATH"
  export FAKE_BIN SAVED_PATH

  cat > "$FAKE_BIN/docker" <<'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *"--filter"*"com.homekase.service"*"--format"*"{{.Names}}"* ]]; then
  echo "jellyfin"
elif [[ "$*" == *"inspect"*"--format"*"com.homekase.service"* ]]; then
  echo "jellyfin"
elif [[ "$*" == *"inspect"*"--format"*"com.homekase.port"* ]]; then
  echo "8096"
elif [[ "$*" == *"inspect"*"--format"*"com.homekase.tailscale"* ]]; then
  echo "false"
elif [[ "$*" == *"inspect"*"--format"*"{{.State.Running}}"* ]]; then
  echo "true"
else
  echo ""
fi
FAKE
  chmod +x "$FAKE_BIN/docker"

  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG

  export PATH="$FAKE_BIN:$SAVED_PATH"
}

teardown() {
  rm -rf "$FAKE_BIN"
  rm -f "$HOMEKASE_CONFIG"
}

# Override _status_collect_system in each test to avoid /proc deps on macOS
_system_stub='
_status_collect_system() {
  _hn="testserver"
  _uptime="1 day, 0 hours"
  _load1="0.12"; _load5="0.15"; _load15="0.18"
  _ram_used_mb=4096; _ram_total_mb=16384
}
'

@test "cmd_status exits 0" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    $_system_stub
    cmd_status
  "
  [ "$status" -eq 0 ]
}

@test "cmd_status --json exits 0" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    $_system_stub
    cmd_status --json
  "
  [ "$status" -eq 0 ]
}

@test "cmd_status --json output is valid JSON" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    $_system_stub
    cmd_status --json
  "
  [ "$status" -eq 0 ]
  echo "$output" | jq . > /dev/null
}

@test "cmd_status --json system section includes hostname" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    $_system_stub
    cmd_status --json
  "
  [ "$status" -eq 0 ]
  hostname_val="$(echo "$output" | jq -r '.system.hostname')"
  [ -n "$hostname_val" ]
  [ "$hostname_val" != "null" ]
}

@test "cmd_status pretty output contains System section" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    $_system_stub
    cmd_status
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"System"* ]]
}

@test "cmd_status pretty output contains Services section" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    $_system_stub
    cmd_status
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Services"* ]]
}
