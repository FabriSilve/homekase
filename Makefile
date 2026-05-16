SHELL := /bin/bash
.PHONY: help lint shellcheck fish-check test bats-check docker-test dry-run all check

help:
	@echo "homekase — make targets"
	@echo ""
	@echo "  lint          Run ShellCheck on all shell scripts"
	@echo "  fish-check    Validate fish syntax"
	@echo "  bash-check    Validate bash syntax"
	@echo "  yaml-check    Validate YAML syntax"
	@echo "  bats-check    Check bats file syntax"
	@echo "  test          Run all unit tests (bats)"
	@echo "  dry-run       Run setup.sh --dry-run (requires root)"
	@echo "  docker-test   Run integration test in Docker container"
	@echo "  setup-dev     Install dev dependencies (shellcheck, bats)"
	@echo "  check         Run all lint + syntax checks"
	@echo "  all           Run everything (lint + test + docker-test)"
	@echo ""

lint: shellcheck fish-check bash-check yaml-check
	@echo ""
	@echo "✓ All lint checks passed"

shellcheck:
	@echo ":: ShellCheck..."
	@if command -v shellcheck &>/dev/null; then \
		fail=0; \
		for f in $$(find . -name '*.sh' -not -path './.git/*'); do \
			if shellcheck -x "$$f"; then \
				echo "  ✓ $$f"; \
			else \
				echo "  ✗ $$f"; fail=1; \
			fi; \
		done; \
		[ "$$fail" -eq 0 ] || exit 1; \
	else \
		echo "  ! shellcheck not installed — skipping"; \
	fi

fish-check:
	@echo ":: Fish syntax..."
	@fail=0; \
	for f in $$(find . -name '*.fish' -not -path './.git/*'); do \
		if fish -n "$$f" &>/dev/null; then \
			echo "  ✓ $$f"; \
		else \
			echo "  ✗ $$f"; fail=1; \
		fi; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1

bash-check:
	@echo ":: Bash syntax..."
	@fail=0; \
	for f in $$(find . -name '*.sh' -not -path './.git/*'); do \
		if bash -n "$$f" &>/dev/null; then \
			echo "  ✓ $$f"; \
		else \
			echo "  ✗ $$f"; fail=1; \
		fi; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1

yaml-check:
	@echo ":: YAML syntax..."
	@fail=0; \
	if python3 -c "import yaml" &>/dev/null; then \
		for f in $$(find . -name '*.yml' -not -path './.git/*' -not -path './templates/*'); do \
			if python3 -c "import yaml; yaml.safe_load(open('$$f'))" &>/dev/null; then \
				echo "  ✓ $$f"; \
			else \
				echo "  ✗ $$f"; fail=1; \
			fi; \
		done; \
		for f in $$(find ./templates -name '*.yml'); do \
			echo "  ~ $$f (template — skipped)"; \
		done; \
	else \
		for f in $$(find . -name '*.yml' -not -path './.git/*'); do \
			echo "  - $$f (skipped — install pyyaml)"; \
		done; \
	fi; \
	[ "$$fail" -eq 0 ] || exit 1

test: bats-check
	@echo ":: Bats unit tests..."
	@if command -v bats &>/dev/null; then \
		for f in tests/test_*.bats; do \
			echo "  running $$(basename $$f .bats)..."; \
			bats --timing "$$f" || exit 1; \
		done; \
	else \
		echo "  ! bats not installed — skipping"; \
		echo "  Install with: sudo apt install bats"; \
	fi

bats-check:
	@echo ":: Bats syntax..."
	@fail=0; \
	for f in tests/test_*.bats; do \
		if grep -q '@test' "$$f" 2>/dev/null; then \
			echo "  ✓ $$f (valid bats)"; \
		else \
			echo "  ✗ $$f (missing @test)"; fail=1; \
		fi; \
	done; \
	[ "$$fail" -eq 0 ] || exit 1

setup-dev:
	@echo ":: Checking dev dependencies..."
	@fail=0; \
	for cmd in shellcheck bats fish; do \
		if command -v "$$cmd" &>/dev/null; then \
			echo "  ✓ $$cmd"; \
		else \
			echo "  ! $$cmd — install it for your distro"; \
			fail=1; \
		fi; \
	done; \
	if [ "$$fail" -eq 0 ]; then \
		echo "✓ All dev tools ready"; \
	else \
		echo "! Install missing tools to run full test suite"; \
	fi

dry-run:
	@echo ":: Dry run (preview mode)..."
	@if [ "$(shell whoami)" = "root" ]; then \
		bash setup.sh --dry-run; \
	else \
		echo "  Run with sudo: sudo make dry-run"; \
		exit 1; \
	fi

docker-test:
	@echo ":: Docker integration test..."
	@if command -v docker &>/dev/null; then \
		docker compose -f tests/docker-compose.test.yml build && \
		docker compose -f tests/docker-compose.test.yml run --rm homekase-test && \
		docker compose -f tests/docker-compose.test.yml down; \
	else \
		echo "  ! docker not available — skipping"; \
	fi

check: lint bash-check test
	@echo ""
	@echo "✓ All checks passed"

all: lint test docker-test
	@echo ""
	@echo "✓ homekase is fully validated"
