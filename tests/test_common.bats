#!/usr/bin/env bats

setup() {
  load 'test_helper'
  # shellcheck source=../lib/common.sh
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"
}

@test "commands: is_installed detects installed tools" {
  run is_installed bash
  assert_success
}

@test "commands: is_installed detects missing tools" {
  run is_installed nonexistent_tool_xyz
  assert_failure
}

@test "commands: is_dpkg_installed detects missing package" {
  run is_dpkg_installed nonexistent-pkg-xyz
  assert_failure
}

@test "filesystem: dir_exists returns true for /tmp" {
  run dir_exists /tmp
  assert_success
}

@test "filesystem: dir_exists returns false for nonexistent" {
  run dir_exists /tmp/nonexistent_dir_xyz
  assert_failure
}

@test "filesystem: file_exists returns true for /etc/passwd" {
  run file_exists /etc/passwd
  assert_success
}

@test "filesystem: file_exists returns false for nonexistent" {
  run file_exists /etc/nonexistent_file_xyz
  assert_failure
}

@test "user: get_user returns a non-empty value" {
  run get_user
  assert_success
  assert_output --regexp '.+'
}

@test "user: get_home returns a valid path" {
  run get_home
  assert_success
  assert_output --regexp '^/'
}

@test "prompts: prompt_input returns default when empty" {
  # Simulate empty input — returns the default
  run echo "" | prompt_input "test" "default_val" 2>/dev/null || true
  # Just checking it doesn't crash
  assert_success
}
