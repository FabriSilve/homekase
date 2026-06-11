#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG
}

teardown() {
  rm -f "$HOMEKASE_CONFIG"
}

@test "config_get reads paths.data" {
  result="$(config_get 'paths.data')"
  [ "$result" = "/data" ]
}

@test "config_get reads paths.storage" {
  result="$(config_get 'paths.storage')"
  [ "$result" = "/storage" ]
}

@test "config_set writes and config_get reads back" {
  config_set 'tailscale.installed' 'true'
  result="$(config_get 'tailscale.installed')"
  [ "$result" = "true" ]
}

@test "config_app_installed returns 1 for unknown app" {
  run config_app_installed "jellyfin"
  [ "$status" -eq 1 ]
}

@test "config_app_set then config_app_installed returns 0" {
  config_app_set "jellyfin" "installed" "true"
  run config_app_installed "jellyfin"
  [ "$status" -eq 0 ]
}

@test "config_app_get reads value set by config_app_set" {
  config_app_set "jellyfin" "port" "8096"
  result="$(config_app_get 'jellyfin' 'port')"
  [ "$result" = "8096" ]
}

@test "config_init creates file from template when missing" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  HOMEKASE_CONFIG="$tmpdir/homekase.yml"
  export HOMEKASE_CONFIG
  config_init
  [ -f "$HOMEKASE_CONFIG" ]
  rm -rf "$tmpdir"
}

@test "config_init is idempotent when file exists" {
  config_set 'ufw.enabled' 'true'
  config_init
  result="$(config_get 'ufw.enabled')"
  [ "$result" = "true" ]
}
