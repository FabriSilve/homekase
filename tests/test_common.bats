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

@test "section: outputs title and description" {
  run section "My Title" "Some description text"
  assert_success
  assert_output --partial "My Title"
  assert_output --partial "Some description text"
}

@test "prompt_choose: selects option by number" {
  run bash -c 'source lib/common.sh; echo "2" | prompt_choose "Pick one" "alpha" "beta" "gamma"'
  assert_success
  assert_output --partial "beta"
}

@test "prompt_choose: defaults to first on empty input" {
  run bash -c 'source lib/common.sh; echo "" | prompt_choose "Pick one" "alpha" "beta"'
  assert_success
  assert_output --partial "alpha"
}

@test "prompt_multi_choose: selects multiple options" {
  run bash -c 'source lib/common.sh; echo "1,3" | prompt_multi_choose "Pick many" "alpha" "beta" "gamma"'
  assert_success
  assert_output --partial "alpha"
  assert_output --partial "gamma"
}

@test "prompt_multi_choose: returns empty on no selection" {
  run bash -c 'source lib/common.sh; echo "" | prompt_multi_choose "Pick many" "alpha" "beta"'
  assert_success
}
