#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
}

@test "is_installed returns 0 for bash" {
  run is_installed bash
  [ "$status" -eq 0 ]
}

@test "is_installed returns 1 for nonexistent command" {
  run is_installed __nonexistent_xyz__
  [ "$status" -eq 1 ]
}

@test "gum_available returns 1 when gum not in PATH" {
  PATH="/nonexistent" run gum_available
  [ "$status" -eq 1 ]
}

@test "info writes to stdout" {
  run info "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test message"* ]]
}

@test "ok writes to stdout" {
  run ok "all good"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all good"* ]]
}

@test "warn writes to stdout" {
  run warn "watch out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"watch out"* ]]
}

@test "error writes to stderr" {
  run bash -c "source '$PROJECT_ROOT/lib/common.sh'; error 'bad thing'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bad thing"* ]]
}

@test "require_root exits 1 when not root" {
  run bash -c "EUID=1000 bash -c 'source \"$PROJECT_ROOT/lib/common.sh\"; require_root'"
  [ "$status" -eq 1 ]
}
