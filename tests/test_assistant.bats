#!/usr/bin/env bats

setup() {
  load 'test_helper'
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"
  SELECTED_SERVICES=()
  source "${BATS_TEST_DIRNAME}/../lib/assistant.sh"
}

@test "assistant: estimate_services_ram returns base overhead with no services" {
  SELECTED_SERVICES=()
  run estimate_services_ram
  assert_success
  # Base (512) + Traefik/AdGuard (256) = 768
  assert_output "768"
}

@test "assistant: estimate_services_ram includes selected services" {
  SELECTED_SERVICES=("jellyfin" "immich")
  run estimate_services_ram
  assert_success
  # 768 + 512 (jellyfin) + 1500 (immich) = 2780
  assert_output "2780"
}

@test "assistant: recommend_model picks 14b for 16GB available" {
  run recommend_model 16384
  assert_success
  assert_output --partial "qwen2.5:14b"
  assert_output --partial "excellent"
}

@test "assistant: recommend_model picks 7b for 8GB available" {
  run recommend_model 8192
  assert_success
  assert_output --partial "qwen2.5:7b"
  assert_output --partial "good"
}

@test "assistant: recommend_model picks 3b for 5GB available" {
  run recommend_model 5120
  assert_success
  assert_output --partial "qwen2.5:3b"
  assert_output --partial "basic"
}

@test "assistant: recommend_model returns none for 2GB available" {
  run recommend_model 2048
  assert_success
  assert_output --partial "none"
  assert_output --partial "insufficient"
}
