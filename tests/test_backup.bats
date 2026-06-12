#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"

  FAKE_BIN="$(mktemp -d)"
  FAKE_BACKUP_DIR="$(mktemp -d)"
  SAVED_PATH="$PATH"
  export FAKE_BIN FAKE_BACKUP_DIR SAVED_PATH

  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  yq -i ".paths.backup = \"$FAKE_BACKUP_DIR\"" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG

  cat > "$FAKE_BIN/docker" <<'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *"com.homekase.service=testapp"* && "$*" == *"{{.Names}}"* ]]; then
  echo "testapp_app_1"
elif [[ "$*" == *"com.homekase.service="* && "$*" == *"{{.Names}}"* ]]; then
  echo ""
elif [[ "$*" == *"inspect"*"backup.type"* ]]; then
  echo "snapshot"
elif [[ "$*" == *"inspect"*"backup.data"* ]]; then
  echo "/tmp"
elif [[ "$*" == *"inspect"*"backup.storage"* ]]; then
  echo ""
elif [[ "$*" == *"inspect"*"backup.db-type"* ]]; then
  echo "none"
elif [[ "$*" == *"com.homekase.service"* && "$*" == *"{{.Names}}"* ]]; then
  echo ""
else
  echo ""
fi
FAKE
  chmod +x "$FAKE_BIN/docker"

  cat > "$FAKE_BIN/rsync" <<'FAKE'
#!/usr/bin/env bash
echo "rsync called: $*"
exit 0
FAKE
  chmod +x "$FAKE_BIN/rsync"

  cat > "$FAKE_BIN/tar" <<'FAKE'
#!/usr/bin/env bash
prev=""
for arg in "$@"; do
  if [[ "$prev" == -*f* ]]; then
    touch "$arg"
  fi
  prev="$arg"
done
exit 0
FAKE
  chmod +x "$FAKE_BIN/tar"

  export PATH="$FAKE_BIN:$SAVED_PATH"

  rm -f /tmp/homekase-backup.lock
}

teardown() {
  rm -rf "$FAKE_BIN" "$FAKE_BACKUP_DIR"
  rm -f "$HOMEKASE_CONFIG"
  rm -f /tmp/homekase-backup.lock
}

@test "cmd_backup unknown app exits 1 with error message" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup unknown_app_xyz
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown_app_xyz"* ]]
}

@test "cmd_backup with no apps exits 0 with nothing-to-backup message" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing"* || "$output" == *"no services"* || "$output" == *"Nothing"* ]]
}

@test "cmd_backup testapp creates destination directory" {
  bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp
  "
  local found
  found="$(find "$FAKE_BACKUP_DIR/testapp" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
  [ -n "$found" ]
}

@test "cmd_backup testapp snapshot creates data.tar.gz" {
  bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp
  "
  local found
  found="$(find "$FAKE_BACKUP_DIR/testapp" -name 'data.tar.gz' 2>/dev/null | head -1)"
  [ -n "$found" ]
}

@test "cmd_backup --incremental testapp calls rsync not tar" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp --incremental
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"rsync called"* ]]
}

@test "cmd_backup testapp writes to backup.log" {
  bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:$SAVED_PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp
  "
  [ -f "$FAKE_BACKUP_DIR/backup.log" ]
}
