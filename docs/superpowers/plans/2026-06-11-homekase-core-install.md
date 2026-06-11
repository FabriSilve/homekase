# homekase CLI — Plan 1: Core & Install

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the installable bash CLI — `install.sh`, main dispatcher, shared utilities, YAML config system, `--help`, `homekase update`, and `homekase uninstall`.

**Architecture:** Bash script collection installed to `/opt/homekase` by `install.sh`. A symlink at `/usr/local/bin/homekase` makes it universally accessible. Shared config lives at `/etc/homekase/homekase.yml`, parsed by `yq` v4. Each subcommand module is sourced on demand by the main entry point. The `.ssh/` directory in the repo root is gitignored and holds the per-server GitHub SSH key used for `git pull`. Subcommand stubs are added so dispatch works end-to-end; Plans 2–5 replace each stub with real implementation.

**Tech Stack:** bash 5+, yq v4 (YAML config), gum (interactive prompts — optional, `read` fallback), bats-core (testing — already installed in project)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `setup.sh` | DELETE | old one-shot entry point |
| `lib/common.sh` | REPLACE | logging, colors, gum wrappers, `require_root`, `is_installed` |
| `lib/config.sh` | REPLACE | `homekase.yml` read/write via yq |
| `lib/system.sh` | DELETE | superseded by `lib/server/` (Plan 2) |
| `lib/users.sh` | DELETE | superseded by `lib/init.sh` (Plan 3) |
| `lib/wizard.sh` | DELETE | absorbed into `lib/common.sh` |
| `lib/common_wizard.sh` | DELETE | absorbed into `lib/common.sh` |
| `lib/tools.sh` | DELETE | superseded by `lib/init.sh` (Plan 3) |
| `lib/network.sh` | DELETE | superseded by `lib/server/network.sh` (Plan 2) |
| `lib/disks.sh` | DELETE | superseded by `lib/server/disk.sh` (Plan 2) |
| `lib/docker.sh` | DELETE | superseded by `lib/server/docker.sh` (Plan 2) |
| `lib/services.sh` | DELETE | superseded by `lib/services/service.sh` (Plan 4) |
| `lib/traefik.sh` | DELETE | dropped from design |
| `lib/adguard.sh` | DELETE | dropped from design |
| `lib/jellyfin.sh` | DELETE | superseded by `lib/services/jellyfin.sh` (Plan 4) |
| `lib/immich.sh` | DELETE | superseded by `lib/services/immich.sh` (Plan 4) |
| `lib/qbittorrent.sh` | DELETE | superseded by `lib/services/qbittorrent.sh` (Plan 4) |
| `lib/syncthing.sh` | DELETE | replaced by Filebrowser service |
| `lib/beszel.sh` | DELETE | replaced by `homekase status` (Plan 5) |
| `lib/github-runner.sh` | DELETE | dropped from design |
| `lib/assistant.sh` | DELETE | superseded by `lib/services/assistant.sh` (Plan 4) |
| `lib/backup.sh` | DELETE | superseded by new `lib/backup.sh` (Plan 5) |
| `lib/tailscale.sh` | DELETE | superseded by `lib/server/vpn.sh` (Plan 2) |
| `scripts/homekase-backup.sh` | DELETE | logic absorbed into `lib/backup.sh` (Plan 5) |
| `functions/homekase.fish` | DELETE | replaced by bash CLI |
| `templates/app/` | DELETE | `homekase app create` dropped from design |
| `homekase` | CREATE | main entry point + dispatcher + update + uninstall |
| `lib/common.sh` | CREATE | logging, colors, gum wrappers |
| `lib/config.sh` | CREATE | yq-backed YAML config read/write |
| `templates/homekase.yml.template` | CREATE | default config file template |
| `install.sh` | CREATE | bootstrap: SSH key gen, git clone, symlink, config init |
| `lib/init.sh` | CREATE (stub) | placeholder for Plan 3 |
| `lib/server/server.sh` | CREATE (stub) | placeholder for Plan 2 |
| `lib/services/service.sh` | CREATE (stub) | placeholder for Plan 4 |
| `lib/status.sh` | CREATE (stub) | placeholder for Plan 5 |
| `lib/backup.sh` | CREATE (stub) | placeholder for Plan 5 |
| `tests/test_helper.bash` | REPLACE | update PROJECT_ROOT, drop old lib/config.sh source |
| `tests/test_common.bats` | REPLACE | tests for new lib/common.sh |
| `tests/test_config.bats` | CREATE | tests for new lib/config.sh |
| `tests/test_dispatch.bats` | CREATE | tests for homekase entry point |
| `Makefile` | MODIFY | drop fish-check, setup.sh dry-run; add `make lint` for shellcheck only |
| `.gitignore` | MODIFY | add `.ssh/` |
| `.ssh/` | CREATE (gitignored) | server-generated GitHub SSH key |

---

### Task 1: Delete old files + update scaffolding

**Files:**
- Delete: all files listed as DELETE in the file map above
- Modify: `.gitignore`, `Makefile`, `tests/test_helper.bash`
- Create directories: `lib/server/`, `lib/services/`

- [ ] **Step 1: Remove old files**

```bash
git rm -f \
  setup.sh \
  lib/common.sh lib/config.sh lib/system.sh lib/users.sh \
  lib/wizard.sh lib/common_wizard.sh lib/tools.sh lib/network.sh \
  lib/disks.sh lib/docker.sh lib/services.sh lib/traefik.sh \
  lib/adguard.sh lib/jellyfin.sh lib/immich.sh lib/qbittorrent.sh \
  lib/syncthing.sh lib/beszel.sh lib/github-runner.sh lib/assistant.sh \
  lib/backup.sh lib/tailscale.sh \
  scripts/homekase-backup.sh \
  functions/homekase.fish
git rm -rf templates/app/
```

- [ ] **Step 2: Create new directories**

```bash
mkdir -p lib/server lib/services .ssh
```

- [ ] **Step 3: Update .gitignore**

```
# Add to .gitignore:
.ssh/
```

The full `.gitignore` should be:
```
/_tmp_*
.ssh/
```

- [ ] **Step 4: Update test_helper.bash**

Replace `tests/test_helper.bash` with:
```bash
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
```

- [ ] **Step 5: Update Makefile**

Replace `Makefile` with a version that drops `fish-check`, `dry-run`, and `docker-test` (not applicable to the new bash-only CLI):
```makefile
SHELL := /bin/bash
.PHONY: help lint shellcheck bash-check yaml-check test bats-check setup-dev check all

help:
	@echo "homekase — make targets"
	@echo ""
	@echo "  lint         Run ShellCheck on all shell scripts"
	@echo "  test         Run bats unit tests"
	@echo "  check        Run lint + test"
	@echo "  setup-dev    Check dev dependencies (shellcheck, bats)"
	@echo ""

lint: shellcheck bash-check

shellcheck:
	@echo ":: ShellCheck..."
	@if command -v shellcheck &>/dev/null; then \
		fail=0; \
		for f in $$(find . -name '*.sh' -not -path './.git/*' -o -name 'homekase' -not -path './.git/*' | grep -v '.git'); do \
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
```

- [ ] **Step 6: Verify bats still runs**

```bash
make test
```

Expected: bats finds no `.bats` files matching `tests/test_*.bats` that still load old `lib/config.sh` — some tests will fail due to missing sourced files. That is expected at this stage. The suite should not crash make itself.

- [ ] **Step 7: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove old setup scripts, scaffold new CLI structure"
```

---

### Task 2: lib/common.sh — TDD

**Files:**
- Create: `lib/common.sh`
- Replace: `tests/test_common.bats`

- [ ] **Step 1: Write failing tests**

Replace `tests/test_common.bats` with:
```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
}

@test "is_installed returns 0 for bash" {
  run is_installed bash
  [ "$status" -eq 0 ]
}

@test "is_installed returns 1 for nonexistent command" {
  run is_installed __nonexistent_xyz__
  [ "$status" -eq 1 ]
}

@test "gum_available returns 1 when gum not in PATH" {
  PATH="/nonexistent" run gum_available
  [ "$status" -eq 1 ]
}

@test "info writes to stdout" {
  run info "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test message"* ]]
}

@test "error writes to stderr" {
  run bash -c "source '$PROJECT_ROOT/lib/common.sh'; error 'bad thing'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bad thing"* ]]
}

@test "require_root exits 1 when not root" {
  run bash -c "EUID=1000 bash -c 'source \"$PROJECT_ROOT/lib/common.sh\"; require_root'"
  [ "$status" -eq 1 ]
}

@test "ok writes to stdout" {
  run ok "all good"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all good"* ]]
}

@test "warn writes to stdout" {
  run warn "watch out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"watch out"* ]]
}
```

- [ ] **Step 2: Run — expect failure**

```bash
bats tests/test_common.bats
```

Expected: `lib/common.sh: No such file`

- [ ] **Step 3: Implement lib/common.sh**

Create `lib/common.sh`:
```bash
#!/usr/bin/env bash

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()   { echo -e "${BLUE}ℹ${RESET}  $*"; }
ok()     { echo -e "${GREEN}✓${RESET}  $*"; }
warn()   { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()  { echo -e "${RED}✗${RESET}  $*" >&2; }
header() { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}\n"; }

is_installed() { command -v "$1" &>/dev/null; }
gum_available() { is_installed gum; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    error "This command requires root. Run with sudo."
    exit 1
  fi
}

ask_confirm() {
  local question="${1:-Are you sure?}"
  if gum_available; then
    gum confirm "$question"
  else
    read -r -p "$question [y/N] " reply
    [[ "${reply,,}" == "y" ]]
  fi
}

ask_input() {
  local prompt="$1" default="${2:-}"
  if gum_available; then
    gum input --placeholder "$prompt" --value "$default"
  else
    read -r -p "$prompt [$default]: " reply
    echo "${reply:-$default}"
  fi
}

ask_choose() {
  local prompt="$1"; shift
  if gum_available; then
    printf '%s\n' "$@" | gum choose --header "$prompt"
  else
    echo "$prompt"
    local i=1
    for opt in "$@"; do echo "  $i) $opt"; ((i++)); done
    read -r -p "Choice [1]: " reply
    local idx=$(( ${reply:-1} - 1 ))
    local opts=("$@")
    echo "${opts[$idx]}"
  fi
}
```

- [ ] **Step 4: Run — expect pass**

```bash
bats tests/test_common.bats
```

Expected:
```
 ✓ is_installed returns 0 for bash
 ✓ is_installed returns 1 for nonexistent command
 ✓ gum_available returns 1 when gum not in PATH
 ✓ info writes to stdout
 ✓ error writes to stderr
 ✓ require_root exits 1 when not root
 ✓ ok writes to stdout
 ✓ warn writes to stdout
8 tests, 0 failures
```

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/test_common.bats
git commit -m "feat: add lib/common.sh with logging helpers, gum wrappers, require_root"
```

---

### Task 3: templates/homekase.yml.template + lib/config.sh — TDD

**Files:**
- Create: `templates/homekase.yml.template`
- Create: `tests/test_config.bats`
- Create: `lib/config.sh`

- [ ] **Step 1: Create config template**

Create `templates/homekase.yml.template`:
```yaml
version: "1"
paths:
  data: /data
  storage: /storage
  backup: /backup
  homelab: /opt/homelab
  config: /etc/homekase
ssh_key: /etc/homekase/.ssh/id_ed25519
tailscale:
  installed: "false"
ufw:
  enabled: "false"
apps: {}
```

- [ ] **Step 2: Write failing tests**

Create `tests/test_config.bats`:
```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test-XXXXX.yml)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG
}

teardown() {
  rm -f "$HOMEKASE_CONFIG"
}

@test "config_get reads paths.data" {
  result="$(config_get 'paths.data')"
  [ "$result" = "/data" ]
}

@test "config_get reads nested paths.storage" {
  result="$(config_get 'paths.storage')"
  [ "$result" = "/storage" ]
}

@test "config_set writes and config_get reads back" {
  config_set 'tailscale.installed' 'true'
  result="$(config_get 'tailscale.installed')"
  [ "$result" = "true" ]
}

@test "config_app_installed returns 1 for unknown app" {
  run config_app_installed "jellyfin"
  [ "$status" -eq 1 ]
}

@test "config_app_set then config_app_installed returns 0" {
  config_app_set "jellyfin" "installed" "true"
  run config_app_installed "jellyfin"
  [ "$status" -eq 0 ]
}

@test "config_app_get reads value set by config_app_set" {
  config_app_set "jellyfin" "port" "8096"
  result="$(config_app_get 'jellyfin' 'port')"
  [ "$result" = "8096" ]
}

@test "config_init creates file from template when missing" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  HOMEKASE_CONFIG="$tmpdir/homekase.yml"
  export HOMEKASE_CONFIG
  config_init
  [ -f "$HOMEKASE_CONFIG" ]
  rm -rf "$tmpdir"
}

@test "config_init is idempotent when file exists" {
  config_set 'ufw.enabled' 'true'
  config_init
  result="$(config_get 'ufw.enabled')"
  [ "$result" = "true" ]
}
```

- [ ] **Step 3: Run — expect failure**

```bash
bats tests/test_config.bats
```

Expected: all tests fail (`lib/config.sh: No such file`).

- [ ] **Step 4: Implement lib/config.sh**

Create `lib/config.sh`:
```bash
#!/usr/bin/env bash

HOMEKASE_CONFIG="${HOMEKASE_CONFIG:-/etc/homekase/homekase.yml}"
HOMEKASE_REPO_DIR="${HOMEKASE_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

_config_require_yq() {
  if ! command -v yq &>/dev/null; then
    echo "✗  yq is required but not installed." >&2
    echo "   Install: https://github.com/mikefarah/yq/releases" >&2
    exit 1
  fi
}

config_get() {
  _config_require_yq
  yq ".$1" "$HOMEKASE_CONFIG" 2>/dev/null
}

config_set() {
  _config_require_yq
  yq -i ".$1 = \"$2\"" "$HOMEKASE_CONFIG"
}

config_app_installed() {
  local val
  val="$(config_get "apps.$1.installed" 2>/dev/null)"
  [[ "$val" == "true" ]]
}

config_app_get() {
  config_get "apps.$1.$2"
}

config_app_set() {
  _config_require_yq
  yq -i ".apps.$1.$2 = \"$3\"" "$HOMEKASE_CONFIG"
}

config_init() {
  [[ -f "$HOMEKASE_CONFIG" ]] && return 0
  local template="$HOMEKASE_REPO_DIR/templates/homekase.yml.template"
  if [[ ! -f "$template" ]]; then
    echo "✗  Config template not found: $template" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$HOMEKASE_CONFIG")"
  cp "$template" "$HOMEKASE_CONFIG"
  chmod 644 "$HOMEKASE_CONFIG"
}
```

- [ ] **Step 5: Run — expect pass**

```bash
bats tests/test_config.bats
```

Expected: 8 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/config.sh templates/homekase.yml.template tests/test_config.bats
git commit -m "feat: add config system with yq-backed homekase.yml read/write"
```

---

### Task 4: install.sh

No bats tests (requires root + network + real filesystem). Manual verification steps provided.

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create install.sh**

Create `install.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/homekase"
CONFIG_DIR="/etc/homekase"
SSH_DIR="$CONFIG_DIR/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
REPO_SSH="git@github.com:FabriSilve/homekase.git"
BIN_LINK="/usr/local/bin/homekase"
YQ_VERSION="v4.44.1"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
_info()  { echo -e "${BLUE}ℹ${RESET}  $*"; }
_ok()    { echo -e "${GREEN}✓${RESET}  $*"; }
_error() { echo -e "${RED}✗${RESET}  $*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || _error "Run as root: sudo bash install.sh"

# Already installed?
if [[ -d "$INSTALL_DIR" && -x "$BIN_LINK" ]]; then
  _info "homekase already installed at $INSTALL_DIR"
  _info "Run 'homekase update' to pull the latest version."
  exit 0
fi

# Prerequisites: git
if ! command -v git &>/dev/null; then
  _info "Installing git..."
  apt-get update -qq && apt-get install -y -qq git
fi
_ok "git ready"

# Prerequisites: yq
if ! command -v yq &>/dev/null; then
  _info "Installing yq $YQ_VERSION..."
  YQ_ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
  wget -qO /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}"
  chmod +x /usr/local/bin/yq
fi
_ok "yq ready"

# SSH key for GitHub
_info "Setting up SSH key for GitHub access..."
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ ! -f "$SSH_KEY" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "homekase@$(hostname)" -q
  chmod 600 "$SSH_KEY"
  chmod 644 "${SSH_KEY}.pub"
  _ok "SSH key generated"
else
  _ok "SSH key already exists"
fi

echo
echo -e "${BOLD}Add this public key to your GitHub account:${RESET}"
echo -e "  ${BOLD}https://github.com/settings/keys${RESET}"
echo
cat "${SSH_KEY}.pub"
echo
read -r -p "Press Enter once the key is added to GitHub... "

# Clone repository
_info "Cloning homekase..."
export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new"
git clone "$REPO_SSH" "$INSTALL_DIR"

# Symlink
chmod +x "$INSTALL_DIR/homekase"
ln -sf "$INSTALL_DIR/homekase" "$BIN_LINK"
_ok "homekase linked to $BIN_LINK"

# Initialize config
if [[ ! -f "$CONFIG_DIR/homekase.yml" ]]; then
  mkdir -p "$CONFIG_DIR"
  cp "$INSTALL_DIR/templates/homekase.yml.template" "$CONFIG_DIR/homekase.yml"
  chmod 644 "$CONFIG_DIR/homekase.yml"
  chown root:root "$CONFIG_DIR/homekase.yml"
fi
yq -i ".ssh_key = \"$SSH_KEY\"" "$CONFIG_DIR/homekase.yml"
_ok "Config at $CONFIG_DIR/homekase.yml"

echo
_ok "homekase installed!"
echo
echo -e "  ${BOLD}homekase --help${RESET}      — available commands"
echo -e "  ${BOLD}homekase init${RESET}        — install CLI tools"
echo -e "  ${BOLD}homekase server${RESET}      — configure this server"
echo -e "  ${BOLD}homekase list${RESET}        — browse available services"
echo
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n install.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh with SSH key gen, yq install, git clone, config init"
```

---

### Task 5: homekase main entry point — TDD

**Files:**
- Create: `homekase`
- Create: `tests/test_dispatch.bats`

- [ ] **Step 1: Write failing dispatch tests**

Create `tests/test_dispatch.bats`:
```bash
#!/usr/bin/env bats

load 'test_helper'

HOMEKASE="$PROJECT_ROOT/homekase"

@test "homekase exits 0 with no args" {
  run bash "$HOMEKASE"
  [ "$status" -eq 0 ]
}

@test "homekase exits 0 with --help" {
  run bash "$HOMEKASE" --help
  [ "$status" -eq 0 ]
}

@test "homekase exits 0 with help" {
  run bash "$HOMEKASE" help
  [ "$status" -eq 0 ]
}

@test "homekase --help shows init" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"init"* ]]
}

@test "homekase --help shows server" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"server"* ]]
}

@test "homekase --help shows list" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"list"* ]]
}

@test "homekase --help shows status" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"status"* ]]
}

@test "homekase --help shows update" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"update"* ]]
}

@test "homekase --help shows uninstall" {
  run bash "$HOMEKASE" --help
  [[ "$output" == *"uninstall"* ]]
}

@test "homekase exits 1 for unknown command" {
  run bash "$HOMEKASE" __invalid_cmd_xyz__
  [ "$status" -eq 1 ]
}

@test "homekase unknown command output contains error" {
  run bash "$HOMEKASE" __invalid_cmd_xyz__
  [[ "$output" == *"Unknown command"* ]]
}
```

- [ ] **Step 2: Run — expect failure**

```bash
bats tests/test_dispatch.bats
```

Expected: all fail (`homekase: No such file`).

- [ ] **Step 3: Create homekase**

Create `homekase`:
```bash
#!/usr/bin/env bash
set -euo pipefail

HOMEKASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMEKASE_DIR
export HOMEKASE_REPO_DIR="$HOMEKASE_DIR"

source "$HOMEKASE_DIR/lib/common.sh"
source "$HOMEKASE_DIR/lib/config.sh"

cmd_help() {
  local B="$BOLD" R="$RESET"
  echo
  echo -e "${B}homekase${R} — homelab CLI"
  echo
  echo -e "${B}USAGE${R}"
  echo "  homekase <command> [options]"
  echo
  echo -e "${B}COMMANDS${R}"
  printf "  %-22s %s\n" "init"            "Install CLI tools (git, docker, fzf, ...)"
  printf "  %-22s %s\n" "server <cmd>"    "Server setup: ssh firewall network vpn swap disk docker"
  printf "  %-22s %s\n" "list"            "List available and installed services"
  printf "  %-22s %s\n" "add <name>"      "Install a service"
  printf "  %-22s %s\n" "remove <name>"   "Remove a service"
  printf "  %-22s %s\n" "status"          "Server and services status  (--json for structured output)"
  printf "  %-22s %s\n" "backup [app]"    "Snapshot app data  (--incremental for delta backup)"
  printf "  %-22s %s\n" "update"          "Pull latest homekase from GitHub"
  printf "  %-22s %s\n" "uninstall"       "Remove homekase from this server"
  echo
  echo "  Run 'homekase <command> --help' for command-specific help."
  echo
}

cmd_update() {
  require_root
  local ssh_key
  ssh_key="$(config_get 'ssh_key')"
  header "Updating homekase"
  info "Pulling latest from GitHub..."
  GIT_SSH_COMMAND="ssh -i $ssh_key -o StrictHostKeyChecking=accept-new" \
    git -C "$HOMEKASE_DIR" pull --ff-only
  ok "homekase updated."
}

cmd_uninstall() {
  require_root
  warn "Removes homekase CLI and its install directory."
  warn "Service data in /data, /storage, /backup is NOT touched."
  echo
  ask_confirm "Uninstall homekase?" || { info "Cancelled."; return 0; }
  rm -f /usr/local/bin/homekase
  rm -rf "$HOMEKASE_DIR"
  info "Config kept at /etc/homekase — remove manually if desired:"
  info "  sudo rm -rf /etc/homekase"
  ok "homekase uninstalled."
}

cmd="${1:-help}"
shift || true
[[ "$cmd" != "--help" && "$cmd" != "-h" ]] || cmd="help"

case "$cmd" in
  init)      source "$HOMEKASE_DIR/lib/init.sh";                  cmd_init "$@" ;;
  server)    source "$HOMEKASE_DIR/lib/server/server.sh";          cmd_server "$@" ;;
  list)      source "$HOMEKASE_DIR/lib/services/service.sh";       cmd_list "$@" ;;
  add)       source "$HOMEKASE_DIR/lib/services/service.sh";       cmd_add "$@" ;;
  remove)    source "$HOMEKASE_DIR/lib/services/service.sh";       cmd_remove "$@" ;;
  status)    source "$HOMEKASE_DIR/lib/status.sh";                 cmd_status "$@" ;;
  backup)    source "$HOMEKASE_DIR/lib/backup.sh";                 cmd_backup "$@" ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  help)      cmd_help ;;
  *)
    error "Unknown command: $cmd"
    echo
    cmd_help
    exit 1
    ;;
esac
```

- [ ] **Step 4: Make executable**

```bash
chmod +x homekase
```

- [ ] **Step 5: Run — expect pass**

```bash
bats tests/test_dispatch.bats
```

Expected: 11 tests, 0 failures.

- [ ] **Step 6: Run full suite**

```bash
make test
```

Expected: all existing tests pass; stubs-sourcing tests skipped until next task.

- [ ] **Step 7: Commit**

```bash
git add homekase tests/test_dispatch.bats
git commit -m "feat: add homekase CLI entry point with dispatch, help, update, uninstall"
```

---

### Task 6: Stub subcommand modules

Prevents `homekase server`, `homekase init`, etc. from crashing with "file not found" until Plans 2–5 replace each stub.

**Files:**
- Create: `lib/init.sh`
- Create: `lib/server/server.sh`
- Create: `lib/services/service.sh`
- Create: `lib/status.sh`
- Create: `lib/backup.sh`

- [ ] **Step 1: Create stubs**

Create `lib/init.sh`:
```bash
#!/usr/bin/env bash
cmd_init() {
  warn "homekase init: not yet implemented (Plan 3)"
}
```

Create `lib/server/server.sh`:
```bash
#!/usr/bin/env bash
cmd_server() {
  warn "homekase server: not yet implemented (Plan 2)"
}
```

Create `lib/services/service.sh`:
```bash
#!/usr/bin/env bash
cmd_list()   { warn "homekase list: not yet implemented (Plan 4)"; }
cmd_add()    { warn "homekase add: not yet implemented (Plan 4)"; }
cmd_remove() { warn "homekase remove: not yet implemented (Plan 4)"; }
```

Create `lib/status.sh`:
```bash
#!/usr/bin/env bash
cmd_status() {
  warn "homekase status: not yet implemented (Plan 5)"
}
```

Create `lib/backup.sh`:
```bash
#!/usr/bin/env bash
cmd_backup() {
  warn "homekase backup: not yet implemented (Plan 5)"
}
```

- [ ] **Step 2: Smoke test all dispatch paths**

```bash
bash homekase --help
bash homekase init
bash homekase server
bash homekase list
bash homekase add jellyfin
bash homekase remove jellyfin
bash homekase status
bash homekase backup
```

Expected: help prints full table; all other commands print "not yet implemented" warning.

- [ ] **Step 3: Run full test suite**

```bash
make test
```

Expected: all tests pass. Zero failures.

- [ ] **Step 4: Remove stale bats test files from old codebase**

Check if any old `.bats` files reference deleted lib files and delete them if they can't be fixed:
```bash
grep -l 'lib/disks\|lib/network\|lib/wizard\|lib/services.sh\|lib/tools\|lib/system' tests/*.bats 2>/dev/null || echo "none"
```

If any files are found, remove them (their replacements will come in Plans 2–5):
```bash
# Example — only run if grep finds matches:
# git rm tests/test_disks.bats tests/test_network.bats tests/test_wizard.bats tests/test_services.bats
```

Re-run `make test` and confirm zero failures.

- [ ] **Step 5: Commit**

```bash
git add lib/init.sh lib/server/server.sh lib/services/service.sh lib/status.sh lib/backup.sh
git commit -m "chore: add stub subcommand modules — dispatch works end-to-end"
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|-------------|------|
| `install.sh` with SSH key gen + git clone + symlink | Task 4 |
| `homekase --help` with all commands listed | Task 5 |
| `homekase update` pulls latest via SSH key | Task 5 |
| `homekase uninstall` removes symlink + install dir | Task 5 |
| `homekase.yml` shared config at `/etc/homekase` | Task 3 |
| Config readable by all users (chmod 644) | Task 3, 4 |
| Install accessible to all users via `/usr/local/bin` | Task 4 |
| `.ssh/` gitignored | Task 1 |
| Old files removed | Task 1 |
| `yq` installed as prerequisite | Task 4 |
| Stubs prevent crashes before Plans 2–5 | Task 6 |
| Test suite passes after all tasks | Tasks 2, 3, 5, 6 |

**Not in this plan (by design):**
- `homekase server` subcommands → Plan 2
- `homekase init` tool selection → Plan 3
- `homekase list/add/remove` services → Plan 4
- `homekase status` + `homekase backup` → Plan 5

### Placeholder scan

None. Every step has real code or real commands with expected output.

### Type consistency

`config_get`, `config_set`, `config_app_installed`, `config_app_get`, `config_app_set` defined in Task 3 and referenced consistently in Tasks 4 and 5.

---

## Remaining Plans (scope outlines)

### Plan 2: Server Commands
**Scope:** `homekase server ssh|firewall|network|vpn|swap|disk|docker`

Key behaviors:
- `ssh` — key-only auth, fail2ban (asks to install fail2ban if missing)
- `firewall` — UFW deny-in default; detects Tailscale and adds `ufw allow in on tailscale0`; if Tailscale added later and UFW running, same rule applied by `vpn`
- `network` — static IP via netplan; shows router instructions for DHCP reservation; no DNS overrides
- `vpn` — asks "install Tailscale?" → install + `tailscale up`; updates `tailscale.installed` in config; adds UFW tailscale0 rule if UFW enabled
- `swap` — 6GB swapfile, swappiness 10
- `disk` — `lsblk` overview + `df -h` per mount + `du` top-5 per volume (read-only, no partitioning)
- `docker` — Docker Engine + Compose plugin + Buildx; sets log driver to json-file max 10MB/3 files; creates docker network `homelab-net`

Key files: `lib/server/server.sh`, `lib/server/ssh.sh`, `lib/server/firewall.sh`, `lib/server/network.sh`, `lib/server/vpn.sh`, `lib/server/swap.sh`, `lib/server/disk.sh`, `lib/server/docker.sh`

Depends on: Plan 1 complete.

---

### Plan 3: Init Command
**Scope:** `homekase init` — gum multi-select tool installer

Pre-selected (on by default): `git`, `fzf`, `bat`, `ripgrep`, `btop`, `jq`, `mtr`, `ncdu`, `gum`, docker+compose+buildx (via `homekase server docker`), `parted`/`lsblk`/`findmnt`

Optional (off by default): `fish`, `lazygit`, `lazydocker`, `nvim`+LazyVim (symlinked to `/opt/homekase/nvim` for shared config), `starship`, `gh`

Behavior: shows gum multi-select list with tool name + description + "(installed)" suffix if already present. Installs selected tools. Fish config written to `/etc/fish/conf.d/homekase.fish` (system-wide). Nvim installs to `/opt/homekase/nvim` with `~/.config/nvim` + `/root/.config/nvim` symlinked to it.

Key files: `lib/init.sh`

Depends on: Plan 1 complete, `gum` available (install.sh doesn't install gum — user installs via `homekase init` bootstrap prompt or manually).

---

### Plan 4: Services System
**Scope:** `homekase list`, `homekase add <name>`, `homekase remove <name>` + per-service wizards

Services:
| Name | Key wizard questions | Port | Notes |
|------|---------------------|------|-------|
| jellyfin | data path, storage path (shares `/storage` with qbittorrent), tailscale serve? | 8096 | |
| immich | data path, photos path, tailscale serve? | 3001 | PostgreSQL pgvecto-rs + Redis |
| qbittorrent | storage path, VPN? (Gluetun WireGuard), tailscale serve? | 8080 | shares `/storage/torrents` readable by jellyfin |
| filebrowser | storage path, admin password, tailscale serve? | 8080 | family file portal |
| vikunja | data path, admin password, tailscale serve? | 3456 | SQLite — no separate DB needed |
| assistant | RAM check (auto-selects model), tailscale serve? | 8080 | Ollama + Whisper + Piper |

Each service: requirements check (RAM/disk), gum wizard, writes `/opt/homelab/<name>/docker-compose.yml` + `.env`, runs `docker compose up -d`, updates `homekase.yml` via `config_app_set`.

`homekase list` renders a table: name, description, installed (yes/no), port, tailscale URL if enabled.

Key files: `lib/services/service.sh`, `lib/services/jellyfin.sh`, `lib/services/immich.sh`, `lib/services/qbittorrent.sh`, `lib/services/filebrowser.sh`, `lib/services/vikunja.sh`, `lib/services/assistant.sh`

Depends on: Plan 1 + Plan 2 (docker installed).

---

### Plan 5: Status + Backup
**Scope:** `homekase status [--json]`, `homekase backup [app] [--incremental]`

`homekase status` terminal output:
- System: hostname, uptime, CPU load, RAM (used/total)
- Disk: per-mount `df -h` row
- Services: table from `/opt/homelab/*/docker-compose.yml` — name, container status (up/down), port, Tailscale URL if configured

`homekase status --json` — same data as structured JSON for AI assistant to query.

`homekase backup [app]`:
- No app arg: iterates all installed apps from config
- Snapshot: `tar czf /backup/<app>/<YYYYMMDD-HHMMSS>.tar.gz <data_path> <storage_path>`
- Postgres containers: `pg_dump` inside container before tar
- `--incremental`: `rsync --link-dest` hardlink delta to previous snapshot
- Cron-safe: exits 0 even if no apps installed; logs to `/backup/backup.log`

Key files: `lib/status.sh`, `lib/backup.sh`

Depends on: Plan 1 complete, at least some services installed (Plan 4) to test meaningfully.
