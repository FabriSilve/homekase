#!/usr/bin/env bats

setup() {
  load 'test_helper'
  # shellcheck source=../lib/common.sh
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"
  # shellcheck source=../lib/services.sh
  source "${BATS_TEST_DIRNAME}/../lib/services.sh"
}

@test "services: deploy_selected_services handles empty selection" {
  # With empty SELECTED_SERVICES, deploy_selected_services should do nothing
  SELECTED_SERVICES=()
  run deploy_selected_services
  assert_success
}

@test "services: SELECTED_SERVICES is initially empty" {
  # After sourcing, the array should exist and be empty
  run echo "${#SELECTED_SERVICES[@]}"
  assert_output "0"
}

@test "services: deploy_selected_services with jellyfin calls deploy_jellyfin" {
  # Mock deploy_jellyfin to verify it gets called
  deploy_jellyfin() { echo "jellyfin_called"; }

  SELECTED_SERVICES=("jellyfin")
  run deploy_selected_services
  assert_success
  assert_output --partial "jellyfin_called"
}

@test "services: deploy_selected_services with immich calls deploy_immich" {
  deploy_immich() { echo "immich_called"; }

  SELECTED_SERVICES=("immich")
  run deploy_selected_services
  assert_success
  assert_output --partial "immich_called"
}

@test "services: deploy_selected_services handles multiple selections" {
  local calls=""
  deploy_jellyfin() { calls="${calls}jellyfin "; }
  deploy_immich() { calls="${calls}immich "; }

  SELECTED_SERVICES=("jellyfin" "immich")
  deploy_selected_services
  run echo "$calls"
  assert_output "jellyfin immich "
}
