#!/usr/bin/env bats

setup() {
  load 'test_helper'
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../lib/network.sh"
  TEST_TMP=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "network: get_preferred_interface returns ethernet when carrier=1" {
  mkdir -p "$TEST_TMP/enp3s0"
  echo "1" > "$TEST_TMP/enp3s0/carrier"
  mkdir -p "$TEST_TMP/wlp2s0"
  echo "up" > "$TEST_TMP/wlp2s0/operstate"
  export SYS_NET_DIR="$TEST_TMP"
  run get_preferred_interface
  assert_success
  assert_output "enp3s0"
}

@test "network: get_preferred_interface falls back to wifi when no ethernet carrier" {
  mkdir -p "$TEST_TMP/enp3s0"
  echo "0" > "$TEST_TMP/enp3s0/carrier"
  mkdir -p "$TEST_TMP/wlp2s0"
  echo "up" > "$TEST_TMP/wlp2s0/operstate"
  export SYS_NET_DIR="$TEST_TMP"
  run get_preferred_interface
  assert_success
  assert_output "wlp2s0"
}

@test "network: setup_static_ip skips netplan write when file already exists" {
  touch "$TEST_TMP/99-homekase-static.yaml"
  export NETPLAN_FILE="$TEST_TMP/99-homekase-static.yaml"
  ip() {
    case "$*" in
      "-4 addr show enp3s0") echo "    inet 192.168.1.50/24 scope global enp3s0" ;;
      "route") echo "default via 192.168.1.1 dev enp3s0" ;;
      "link show enp3s0") echo "    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff" ;;
    esac
  }
  get_preferred_interface() { echo "enp3s0"; }
  export -f ip get_preferred_interface
  run setup_static_ip
  assert_success
  assert_output --partial "already configured"
}

@test "network: setup_static_ip warns and continues when user declines" {
  export NETPLAN_FILE="$TEST_TMP/nonexistent/99-homekase-static.yaml"
  ip() {
    case "$*" in
      "-4 addr show enp3s0") echo "    inet 192.168.1.50/24 scope global enp3s0" ;;
      "route") echo "default via 192.168.1.1 dev enp3s0" ;;
      "link show enp3s0") echo "    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff" ;;
    esac
  }
  get_preferred_interface() { echo "enp3s0"; }
  prompt_yes_no() { return 1; }
  export -f ip get_preferred_interface prompt_yes_no
  run setup_static_ip
  assert_success
  assert_output --partial "may change"
}

@test "network: show_router_instructions prints gateway, MAC, server IP, and fallback DNS" {
  run show_router_instructions "enp3s0" "192.168.1.50/24" "192.168.1.1" "aa:bb:cc:dd:ee:ff"
  assert_success
  assert_output --partial "192.168.1.1"
  assert_output --partial "aa:bb:cc:dd:ee:ff"
  assert_output --partial "192.168.1.50"
  assert_output --partial "8.8.8.8"
}
