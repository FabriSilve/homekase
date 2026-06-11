# Minimal bats helpers — assert_success, assert_failure, assert_output, assert_equal

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

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
  local expected="$1" actual="$2"
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
      echo "got: $output"
      return 1
    fi
  elif [[ "$1" == "--regexp" ]]; then
    if [[ ! "$output" =~ $2 ]]; then
      echo "expected to match: $2"
      echo "got: $output"
      return 1
    fi
  else
    if [[ "$output" != "$1" ]]; then
      echo "expected: $1"
      echo "got: $output"
      return 1
    fi
  fi
}
