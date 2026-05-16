#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v shellcheck &>/dev/null; then
  echo "Installing ShellCheck..."
  sudo apt update -qq && sudo apt install -y -qq shellcheck
fi

echo ":: Running ShellCheck..."
find "$HERE" -name '*.sh' -not -path '*/node_modules/*' | sort | while read -r f; do
  if shellcheck -x "$f"; then
    echo "  ✓ ${f#"$HERE/"}"
  else
    FAILED=1
  fi
done

find "$HERE" -name '*.fish' -not -path '*/node_modules/*' | sort | while read -r f; do
  # fish has no official shellcheck, but we check the file is readable
  if fish -n "$f" 2>/dev/null; then
    echo "  ✓ ${f#"$HERE/"}"
  else
    echo "  ✗ ${f#"$HERE/"} (syntax error)"
    FAILED=1
  fi
done

echo ""
if [ -n "${FAILED:-}" ]; then
  echo "✗ Some checks failed"
  exit 1
else
  echo "✓ All checks passed"
fi
