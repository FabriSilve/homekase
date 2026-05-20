#!/usr/bin/env bats

setup() {
  load 'test_helper'
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"
}

@test "common_wizard.sh sources without error" {
  source "${BATS_TEST_DIRNAME}/../lib/common_wizard.sh"
  assert_success
}

@test "wizard: header is a function after sourcing" {
  source "${BATS_TEST_DIRNAME}/../lib/common_wizard.sh"
  run type -t header
  assert_success
  assert_output "function"
}

@test "wizard: prompt_choose is a function after sourcing" {
  source "${BATS_TEST_DIRNAME}/../lib/common_wizard.sh"
  run type -t prompt_choose
  assert_success
  assert_output "function"
}

@test "wizard: prompt_multi_choose is a function after sourcing" {
  source "${BATS_TEST_DIRNAME}/../lib/common_wizard.sh"
  run type -t prompt_multi_choose
  assert_success
  assert_output "function"
}

@test "wizard: section is a function after sourcing" {
  source "${BATS_TEST_DIRNAME}/../lib/common_wizard.sh"
  run type -t section
  assert_success
  assert_output "function"
}
