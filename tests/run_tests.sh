#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(dirname "${HERE}")"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}┌─────────────────────────────────────────┐${NC}"
echo -e "${BOLD}│${NC}     ${CYAN}homekase test suite${NC}                    ${BOLD}│${NC}"
echo -e "${BOLD}└─────────────────────────────────────────┘${NC}"
echo ""

# ---- Install dependencies ----
if ! command -v bats &>/dev/null; then
  echo -e "${CYAN}::${NC} Installing bats..."
  if command -v apt &>/dev/null; then
    sudo apt update -qq && sudo apt install -y -qq bats
  else
    npm install -g bats 2>/dev/null || pip install bats 2>/dev/null || {
      git clone --depth=1 https://github.com/bats-core/bats-core /tmp/bats
      sudo /tmp/bats/install.sh /usr/local
    }
  fi
fi

if ! command -v shellcheck &>/dev/null; then
  echo -e "${CYAN}::${NC} Installing ShellCheck..."
  sudo apt install -y -qq shellcheck 2>/dev/null || true
fi

if ! command -v fish &>/dev/null; then
  echo -e "${CYAN}::${NC} Installing fish for syntax validation..."
  sudo apt install -y -qq fish 2>/dev/null || true
fi

# ---- Static analysis ----
echo -e "\n${BOLD}━━━ ShellCheck ━━━${NC}"
find "${PROJECT}" -name '*.sh' -not -path '*/node_modules/*' | sort | while read -r f; do
  if shellcheck -x "${f}" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${f#"${PROJECT}/"}"
  else
    FAILED=1
    echo -e "  ${RED}✗${NC} ${f#"${PROJECT}/"}"
  fi
done 2>&1 || true

find "${PROJECT}" -name '*.fish' -not -path '*/node_modules/*' | sort | while read -r f; do
  if fish -n "${f}" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${f#"${PROJECT}/"}"
  else
    FAILED=1
    echo -e "  ${RED}✗${NC} ${f#"${PROJECT}/"} (syntax error)"
  fi
done 2>&1 || true

# ---- Unit tests ----
echo -e "\n${BOLD}━━━ Bats Unit Tests ━━━${NC}"

TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0

for test_file in "${HERE}"/test_*.bats; do
  [[ -f "${test_file}" ]] || continue
  NAME="$(basename "${test_file}" .bats)"
  echo -e "\n${CYAN}::${NC} ${NAME}"

  if bats --timing "${test_file}" 2>&1; then
    ((TEST_PASSED++))
  else
    ((TEST_FAILED++))
    FAILED=1
  fi
  ((TEST_COUNT++))
done

# ---- Summary ----
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ -n "${FAILED:-}" ]]; then
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
else
  echo -e "${GREEN}✓ All tests passed${NC}"
fi
echo "  ${TEST_PASSED}/${TEST_COUNT} test suites"
