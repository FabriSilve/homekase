SHELL := /bin/bash
.PHONY: help lint shellcheck bash-check yaml-check test bats-check setup-dev check all

help:
	@echo "homekase — make targets"
	@echo ""
	@echo "  lint         Run ShellCheck on all shell scripts"
	@echo "  test         Run bats unit tests"
	@echo "  check        Run lint + test"
	@echo "  setup-dev    Check dev dependencies (shellcheck, bats, yq)"
	@echo ""

lint: shellcheck bash-check

shellcheck:
	@echo ":: ShellCheck..."
	@if command -v shellcheck &>/dev/null; then \
		fail=0; \
		for f in $$(find . \( -name '*.sh' -o -name 'homekase' \) -not -path './.git/*'); do \
			if shellcheck -x "$$f" 2>/dev/null; then echo "  ✓ $$f"; \
			else echo "  ✗ $$f"; fail=1; fi; \
		done; \
		[ "$$fail" -eq 0 ] || exit 1; \
	else echo "  ! shellcheck not installed — skipping"; fi

bash-check:
	@echo ":: Bash syntax..."
	@fail=0; \
	for f in $$(find . \( -name '*.sh' -o -name 'homekase' \) -not -path './.git/*'); do \
		if bash -n "$$f" &>/dev/null; then echo "  ✓ $$f"; \
		else echo "  ✗ $$f"; fail=1; fi; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1

yaml-check:
	@echo ":: YAML syntax..."
	@fail=0; \
	if python3 -c "import yaml" &>/dev/null; then \
		for f in $$(find . -name '*.yml' -not -path './.git/*' -not -path './templates/*'); do \
			if python3 -c "import yaml; yaml.safe_load(open('$$f'))" &>/dev/null; then echo "  ✓ $$f"; \
			else echo "  ✗ $$f"; fail=1; fi; \
		done; \
	else echo "  ! pyyaml not found — skipping yaml-check"; fi; \
	[ "$$fail" -eq 0 ] || exit 1

test: bats-check
	@echo ":: Bats unit tests..."
	@if command -v bats &>/dev/null; then \
		bats tests/test_*.bats; \
	else echo "  ! bats not installed. Install: sudo apt install bats"; fi

bats-check:
	@echo ":: Bats syntax..."
	@fail=0; \
	for f in tests/test_*.bats; do \
		[ -f "$$f" ] || continue; \
		if grep -q '@test' "$$f" 2>/dev/null; then echo "  ✓ $$f"; \
		else echo "  ✗ $$f (missing @test)"; fail=1; fi; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1

setup-dev:
	@echo ":: Dev dependencies..."
	@for cmd in shellcheck bats yq; do \
		if command -v "$$cmd" &>/dev/null; then echo "  ✓ $$cmd"; \
		else echo "  ! $$cmd — not found"; fi; \
	done

check: lint test
	@echo "✓ All checks passed"

all: check
