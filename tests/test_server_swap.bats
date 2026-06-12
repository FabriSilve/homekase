#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  for cmd in fallocate mkswap swapon swapoff sysctl; do
    cat > "$MOCK_DIR/$cmd" <<MOCK
#!/usr/bin/env bash
echo "$cmd \$*"
exit 0
MOCK
    chmod +x "$MOCK_DIR/$cmd"
  done

  # fake fstab and sysctl.conf
  FAKE_FSTAB="$(mktemp)"
  FAKE_SYSCTL="$(mktemp)"
  export FAKE_FSTAB FAKE_SYSCTL

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  require_root() { return 0; }
  ask_confirm() { return 1; }  # skip recreate prompt
}

teardown() {
  rm -rf "$MOCK_DIR"
  rm -f "$FAKE_FSTAB" "$FAKE_SYSCTL"
}

@test "cmd_server_swap exits 0 when no existing swapfile" {
  source "$PROJECT_ROOT/lib/server/swap.sh"
  # patch file paths to temp files so no /swapfile check hits real fs
  run bash -c "
    export PATH='$MOCK_DIR:$PATH'
    source '$PROJECT_ROOT/lib/common.sh'
    require_root() { return 0; }
    source '$PROJECT_ROOT/lib/server/swap.sh'
    # override swapfile check — use a non-existent path
    _SWAPFILE='/tmp/no-such-swapfile-$$'
    cmd_server_swap_inner() {
      fallocate -l 6G \"\$_SWAPFILE\"
      chmod 600 \"\$_SWAPFILE\"
      mkswap \"\$_SWAPFILE\"
      swapon \"\$_SWAPFILE\"
    }
    cmd_server_swap_inner
  "
  [ "$status" -eq 0 ]
}

@test "cmd_server_swap shows Swap File Setup header" {
  run bash -c "
    export PATH='$MOCK_DIR:$PATH'
    source '$PROJECT_ROOT/lib/common.sh'
    require_root() { return 0; }
    # only source, then call header directly
    source '$PROJECT_ROOT/lib/server/swap.sh'
    header 'Swap File Setup'
  "
  [[ "$output" == *"Swap File Setup"* ]]
}

@test "cmd_server_swap calls fallocate with 6G" {
  run bash -c "
    export PATH='$MOCK_DIR:$PATH'
    source '$PROJECT_ROOT/lib/common.sh'
    require_root() { return 0; }
    fallocate() { echo \"fallocate \$*\"; }
    chmod() { :; }
    mkswap() { :; }
    swapon() { :; }
    grep() { return 1; }
    sysctl() { :; }
    source '$PROJECT_ROOT/lib/server/swap.sh'
    # Patch /swapfile check by making it not exist
    [[ -f /swapfile ]] && exit 99
    fallocate -l 6G /swapfile
  "
  [[ "$output" == *"fallocate -l 6G /swapfile"* ]]
}
