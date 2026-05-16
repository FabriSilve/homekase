#!/usr/bin/env bats

setup() {
  load 'test_helper'
  # shellcheck source=../lib/common.sh
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"
  # shellcheck source=../lib/disks.sh
  source "${BATS_TEST_DIRNAME}/../lib/disks.sh"
}

@test "disks: detect_disks runs without error" {
  run detect_disks
  assert_success
}

@test "disks: detect_disks finds at least the OS device" {
  # Capture the output and check it contains relevant info
  run bash -c '
    source "${BATS_TEST_DIRNAME}/../lib/common.sh"
    source "${BATS_TEST_DIRNAME}/../lib/disks.sh"
    detect_disks 2>&1 | grep -q "Drive\|Device"
  '
  assert_success
}

@test "disks: run_disk_setup fails gracefully without DATA_DEVICE" {
  # Without DATA_DEVICE set, it should still not crash
  run bash -c '
    source "${BATS_TEST_DIRNAME}/../lib/common.sh"
    source "${BATS_TEST_DIRNAME}/../lib/disks.sh"
    unset DATA_DEVICE
    run_disk_setup 2>&1 || true
  '
  # Should show the detection menu and fail at selection
  assert_failure
}
