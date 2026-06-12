#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  cat > "$MOCK_DIR/lsblk" <<'MOCK'
#!/usr/bin/env bash
echo "NAME   FSTYPE   LABEL   UUID   MOUNTPOINT"
echo "sda"
echo "└─sda1 ext4           /data"
exit 0
MOCK
  chmod +x "$MOCK_DIR/lsblk"

  cat > "$MOCK_DIR/df" <<'MOCK'
#!/usr/bin/env bash
echo "Filesystem      Size  Used Avail Use% Mounted on"
echo "/dev/sda1       100G   20G   80G  20% /data"
exit 0
MOCK
  chmod +x "$MOCK_DIR/df"

  cat > "$MOCK_DIR/du" <<'MOCK'
#!/usr/bin/env bash
echo "1.2G  ./subdir1"
echo "800M  ./subdir2"
exit 0
MOCK
  chmod +x "$MOCK_DIR/du"

  cat > "$MOCK_DIR/mountpoint" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
  chmod +x "$MOCK_DIR/mountpoint"

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/server/disk.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "cmd_server_disk exits 0" {
  run cmd_server_disk
  [ "$status" -eq 0 ]
}

@test "cmd_server_disk output contains Block Devices section" {
  run cmd_server_disk
  [[ "$output" == *"Block Devices"* ]]
}

@test "cmd_server_disk output contains Disk Usage section" {
  run cmd_server_disk
  [[ "$output" == *"Disk Usage"* ]]
}

@test "cmd_server_disk calls lsblk with -f" {
  run cmd_server_disk
  [[ "$output" == *"FSTYPE"* ]]
}

@test "cmd_server_disk calls df -h" {
  run cmd_server_disk
  [[ "$output" == *"Filesystem"* ]]
}
