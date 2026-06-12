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
if [[ "$*" == *"com.homekase.service=jellyfin"* && "$*" == *"{{.Names}}"* ]]; then
  echo "jellyfin"
elif [[ "$*" == *"com.homekase.service="* && "$*" == *"{{.Names}}"* ]]; then
  echo ""
elif [[ "$*" == *"inspect"*"com.homekase.port"* ]]; then
  echo "8096"
else
  echo ""
fi
FAKE
  chmod +x "$FAKE_BIN/docker"

  cat > "$FAKE_BIN/ufw-active" <<'FAKE'
#!/usr/bin/env bash
echo "Status: active"
FAKE
  chmod +x "$FAKE_BIN/ufw-active"

  cat > "$FAKE_BIN/ufw-inactive" <<'FAKE'
#!/usr/bin/env bash
echo "Status: inactive"
FAKE
  chmod +x "$FAKE_BIN/ufw-inactive"

  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG

  export PATH="$FAKE_BIN:$SAVED_PATH"
}

teardown() {
  rm -rf "$FAKE_BIN"
  rm -f "$HOMEKASE_CONFIG"
}

@test "cmd_open unknown service exits 1 with error" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/port.sh'
    cmd_open unknown_xyz
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown_xyz"* ]]
}

@test "cmd_open with no args exits 0 and shows usage" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/port.sh'
    cmd_open
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
}

@test "cmd_open jellyfin when UFW inactive warns and exits 0" {
  ln -sf "$FAKE_BIN/ufw-inactive" "$FAKE_BIN/ufw"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/port.sh'
    cmd_open jellyfin
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"not active"* ]]
}

@test "cmd_open jellyfin when UFW active calls ufw allow" {
  cat > "$FAKE_BIN/ufw" <<'FAKE'
#!/usr/bin/env bash
if [[ "$*" == "status" ]]; then echo "Status: active"; else echo "ufw $*"; fi
FAKE
  chmod +x "$FAKE_BIN/ufw"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/port.sh'
    cmd_open jellyfin
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"allow"* && "$output" == *"8096"* ]]
}

@test "cmd_close unknown service exits 1 with error" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/port.sh'
    cmd_close unknown_xyz
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown_xyz"* ]]
}

@test "cmd_close jellyfin when UFW active calls ufw delete allow" {
  cat > "$FAKE_BIN/ufw" <<'FAKE'
#!/usr/bin/env bash
if [[ "$*" == "status" ]]; then echo "Status: active"; else echo "ufw $*"; fi
FAKE
  chmod +x "$FAKE_BIN/ufw"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/port.sh'
    cmd_close jellyfin
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"delete"* && "$output" == *"8096"* ]]
}
