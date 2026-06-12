#!/usr/bin/env bats

load 'test_helper'

HOMEKASE="$PROJECT_ROOT/homekase"

@test "homekase exits 0 with no args" {
  run bash "$HOMEKASE"
  [ "$status" -eq 0 ]
}

@test "homekase exits 0 with --help" {
  run bash "$HOMEKASE" --help
  [ "$status" -eq 0 ]
}

@test "homekase exits 0 with help" {
  run bash "$HOMEKASE" help
  [ "$status" -eq 0 ]
}

@test "homekase --help shows init" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"init"* ]]
}

@test "homekase --help shows server" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"server"* ]]
}

@test "homekase --help shows list" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"list"* ]]
}

@test "homekase --help shows status" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"status"* ]]
}

@test "homekase --help shows update" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"update"* ]]
}

@test "homekase --help shows uninstall" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"uninstall"* ]]
}

@test "homekase exits 1 for unknown command" {
  run bash "$HOMEKASE" __invalid_cmd_xyz__
  [ "$status" -eq 1 ]
}

@test "homekase unknown command output contains error" {
  run bash "$HOMEKASE" __invalid_cmd_xyz__
  [[ "$output" == *"Unknown command"* ]]
}
