# test_helper.bash — minimal bats assertion helpers
# Provides assert_success, assert_failure, assert_output, etc.

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

assert_output() {
  local expected="$1"
  if [[ "$output" != "$expected" ]]; then
    echo "expected: $expected"
    echo "got:      $output"
    return 1
  fi
}

assert_output --partial() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    echo "expected to contain: $expected"
    echo "got:                $output"
    return 1
  fi
}

assert_output --regexp() {
  local expected="$1"
  if [[ ! "$output" =~ $expected ]]; then
    echo "expected to match: $expected"
    echo "got:              $output"
    return 1
  fi
}
