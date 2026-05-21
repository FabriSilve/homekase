# test_helper.bash — minimal bats assertion helpers
# Provides assert_success, assert_failure, assert_output, etc.

# Source config before any lib (provides HOMELAB_DIR, etc.)
# shellcheck disable=SC1091
source "${BATS_TEST_DIRNAME}/../lib/config.sh"

assert_success() {
  if [ "$status" -ne 0 ]; then
    echo "expected success, got exit code $status"
    echo "output: $output"
    return 1
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    echo "expected failure, got exit code 0"
    echo "output: $output"
    return 1
  fi
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "expected: $expected"
    echo "got:      $actual"
    return 1
  fi
}

assert_output() {
  if [[ "$1" == "--partial" ]]; then
    local expected="$2"
    if [[ "$output" != *"$expected"* ]]; then
      echo "expected to contain: $expected"
      echo "got:                $output"
      return 1
    fi
  elif [[ "$1" == "--regexp" ]]; then
    local expected="$2"
    if [[ ! "$output" =~ $expected ]]; then
      echo "expected to match: $expected"
      echo "got:              $output"
      return 1
    fi
  else
    local expected="$1"
    if [[ "$output" != "$expected" ]]; then
      echo "expected: $expected"
      echo "got:      $output"
      return 1
    fi
  fi
}
