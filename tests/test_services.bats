#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  export HOMEKASE_CONFIG
  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  source "$PROJECT_ROOT/lib/services/_common.sh"
}

teardown() {
  rm -f "$HOMEKASE_CONFIG"
}

@test "next_available_port returns a number when no apps configured" {
  result="$(next_available_port)"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "next_available_port returns a number when apps have ports" {
  config_app_set "jellyfin" "port" "4000"
  config_app_set "immich"   "port" "4010"
  result="$(next_available_port)"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "next_available_port suggests higher port than existing ones" {
  config_app_set "jellyfin" "port" "4000"
  result="$(next_available_port)"
  [ "$result" -gt 4000 ]
}

# ── Dispatcher tests ─────────────────────────────────────────────────────────

@test "cmd_list exits 0" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_success
}

@test "cmd_list output contains jellyfin" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "jellyfin"
}

@test "cmd_list output contains immich" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "immich"
}

@test "cmd_list output contains qbittorrent" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "qbittorrent"
}

@test "cmd_list output contains filebrowser" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "filebrowser"
}

@test "cmd_list output contains vikunja" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "vikunja"
}

@test "cmd_list output contains assistant" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "assistant"
}

@test "cmd_list output contains navidrome" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "navidrome"
}

@test "cmd_add with unknown name exits 1" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_add "__no_such_service__"
  assert_failure
}

@test "cmd_add with unknown name output contains error" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_add "__no_such_service__"
  assert_output --partial "Unknown service"
}

@test "cmd_remove with unknown name exits 1" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_remove "__no_such_service__"
  assert_failure
}

@test "cmd_remove with unknown name output contains error" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_remove "__no_such_service__"
  assert_output --partial "Unknown service"
}

@test "cmd_pause with unknown name exits 1" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_pause "__no_such_service__"
  assert_failure
}

@test "cmd_pause with unknown name output contains error" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_pause "__no_such_service__"
  assert_output --partial "Unknown service"
}

@test "cmd_resume with unknown name exits 1" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_resume "__no_such_service__"
  assert_failure
}

@test "cmd_resume with unknown name output contains error" {
  export HOMEKASE_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_resume "__no_such_service__"
  assert_output --partial "Unknown service"
}
