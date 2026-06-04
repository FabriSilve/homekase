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

@test "luks: setup_luks_auto_unlock exits silently when no crypt devices exist" {
  lsblk() { echo "disk sda"; }
  export -f lsblk
  run setup_luks_auto_unlock
  assert_success
  assert_output ""
}

@test "luks: setup_luks_auto_unlock warns when LUKS found but no TPM2 hardware" {
  lsblk() {
    if [[ "$*" == *"-s"* ]]; then echo "part sda5"
    else echo "crypt sda5_crypt"
    fi
  }
  export -f lsblk
  unset TPM2_TEST_OVERRIDE
  run setup_luks_auto_unlock
  assert_success
  assert_output --partial "passphrase required every"
}

@test "luks: setup_luks_auto_unlock skips device already enrolled with TPM2" {
  local tmpdir tpm_file
  tmpdir=$(mktemp -d)
  tpm_file=$(mktemp)
  # Fake systemd-cryptenroll binary (hyphen prevents export -f)
  printf '#!/bin/bash\necho "0: tpm2"\n' > "$tmpdir/systemd-cryptenroll"
  chmod +x "$tmpdir/systemd-cryptenroll"
  export PATH="$tmpdir:$PATH"
  export TPM2_TEST_OVERRIDE="$tpm_file"
  lsblk() {
    if [[ "$*" == *"-s"* ]]; then echo "part sda5"
    else echo "crypt sda5_crypt"
    fi
  }
  cryptsetup() { echo "Keyslots: tpm2"; }
  export -f lsblk cryptsetup
  run setup_luks_auto_unlock
  assert_success
  assert_output --partial "already enrolled"
  rm -rf "$tmpdir" "$tpm_file"
}
