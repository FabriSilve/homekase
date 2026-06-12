# homekase init — Plan 3: Tool Installer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `homekase init` — a gum-driven interactive tool installer that presents a multi-select menu of pre-selected and optional CLI tools, installs selected ones idempotently, and writes a fish system config when fish is chosen.

**Architecture:** Two tasks with clean separation. Task 1 extends `install.sh` to install gum at bootstrap time, so every subsequent `homekase` invocation has gum available. Task 2 replaces the `lib/init.sh` stub with `cmd_init`, per-tool install functions, and a fish config writer. The file stays flat — one function per tool — because each install method is different enough to warrant explicit code. Task 3 adds the bats test suite.

**Tech Stack:** bash 5+, gum (TUI multi-select — required, installed in Task 1), apt, curl, GitHub Releases API (via redirect to latest tarball), bats-core (tests)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `install.sh` | MODIFY | Add gum install block after yq block |
| `lib/init.sh` | REPLACE | `cmd_init` dispatcher + all `install_tool_*` functions + fish config writer |
| `tests/test_init.bats` | CREATE | Bats unit tests for `lib/init.sh` logic |

---

### Task 1: Add gum to install.sh

Gum must be installed by `install.sh` so it is present from the first `homekase` run. No tests (requires root + network). Manual verification only.

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add gum install block after the yq block**

In `install.sh`, find the lines:

```bash
fi
_ok "yq ready"

# SSH key for GitHub
```

Replace with:

```bash
fi
_ok "yq ready"

# Prerequisites: gum
if ! command -v gum &>/dev/null; then
  _info "Installing gum..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    > /etc/apt/sources.list.d/charm.list
  apt-get update -qq && apt-get install -y -qq gum
fi
_ok "gum ready"

# SSH key for GitHub
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n install.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Verify shellcheck passes**

```bash
shellcheck -x install.sh
```

Expected: no warnings (or same warnings as before — zero new ones).

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: install gum in install.sh before repo clone"
```

---

### Task 2: lib/init.sh — full implementation (TDD in Task 3, implement here)

Replace the stub with the full implementation. Write the code first; tests come in Task 3 (which will validate the testable parts — the non-root logic paths and file writing).

**Files:**
- Replace: `lib/init.sh`

- [ ] **Step 1: Write lib/init.sh**

Replace `lib/init.sh` with:

```bash
#!/usr/bin/env bash
# lib/init.sh — homekase init: interactive tool installer

# ---------------------------------------------------------------------------
# Tool metadata
# ---------------------------------------------------------------------------
# Format: key|display_name|description|default_selected
# default_selected: "yes" = pre-checked, "no" = unchecked
_TOOLS=(
  "git|git|Version control|yes"
  "fzf|fzf|Fuzzy finder|yes"
  "bat|bat|Better cat|yes"
  "ripgrep|ripgrep (rg)|Better grep|yes"
  "btop|btop|System monitor|yes"
  "jq|jq|JSON processor|yes"
  "mtr|mtr|Network diagnostics|yes"
  "ncdu|ncdu|Disk usage analyzer|yes"
  "parted|parted + lsblk + findmnt|Disk tools|yes"
  "fish|fish|Fish shell|no"
  "starship|starship|Shell prompt|no"
  "lazygit|lazygit|Git TUI|no"
  "lazydocker|lazydocker|Docker TUI|no"
  "nvim|neovim + LazyVim|Editor|no"
  "gh|gh|GitHub CLI|no"
)

# Binary checked per-key (some keys install multiple binaries; check the primary one)
_tool_binary() {
  case "$1" in
    ripgrep)   echo "rg" ;;
    parted)    echo "parted" ;;
    nvim)      echo "nvim" ;;
    lazygit)   echo "lazygit" ;;
    lazydocker) echo "lazydocker" ;;
    starship)  echo "starship" ;;
    *)         echo "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_init
# ---------------------------------------------------------------------------
cmd_init() {
  require_root

  # Build the gum choose list: one line per tool
  local -a gum_items=()
  local -a default_keys=()
  for entry in "${_TOOLS[@]}"; do
    local key name desc default_sel
    IFS='|' read -r key name desc default_sel <<< "$entry"
    local binary
    binary="$(_tool_binary "$key")"
    local status_label
    if command -v "$binary" &>/dev/null; then
      status_label="(installed)"
    else
      status_label="(not installed)"
    fi
    gum_items+=("[${key}] ${name} — ${desc} ${status_label}")
    if [[ "$default_sel" == "yes" ]]; then
      default_keys+=("[${key}] ${name} — ${desc} ${status_label}")
    fi
  done

  # Build --selected flags for gum choose
  local -a selected_flags=()
  for item in "${default_keys[@]}"; do
    selected_flags+=(--selected="$item")
  done

  header "homekase init — select tools to install"

  local chosen
  chosen="$(printf '%s\n' "${gum_items[@]}" | \
    gum choose --no-limit \
      --header "Space to toggle, Enter to confirm" \
      "${selected_flags[@]}")" || true

  if [[ -z "$chosen" ]]; then
    info "Nothing selected. Exiting."
    return 0
  fi

  # Parse selected keys from chosen lines
  local -a selected_keys=()
  while IFS= read -r line; do
    # Extract key from "[key] ..."
    local k
    k="${line#\[}"
    k="${k%%\]*}"
    selected_keys+=("$k")
  done <<< "$chosen"

  # Install each selected tool
  local key
  for key in "${selected_keys[@]}"; do
    info "Installing: ${key}..."
    "install_tool_${key}"
  done

  # Post-install: fish system config
  local fish_selected=false
  local nvim_selected=false
  local starship_selected=false
  for key in "${selected_keys[@]}"; do
    [[ "$key" == "fish" ]]     && fish_selected=true
    [[ "$key" == "nvim" ]]     && nvim_selected=true
    [[ "$key" == "starship" ]] && starship_selected=true
  done

  if $fish_selected; then
    _write_fish_config
  fi

  ok "init complete"
}

# ---------------------------------------------------------------------------
# Per-tool install functions
# ---------------------------------------------------------------------------

install_tool_git() {
  apt-get install -y -qq git
  ok "git installed"
}

install_tool_fzf() {
  apt-get install -y -qq fzf
  ok "fzf installed"
}

install_tool_bat() {
  apt-get install -y -qq bat
  ok "bat installed"
}

install_tool_ripgrep() {
  apt-get install -y -qq ripgrep
  ok "ripgrep (rg) installed"
}

install_tool_btop() {
  apt-get install -y -qq btop
  ok "btop installed"
}

install_tool_jq() {
  apt-get install -y -qq jq
  ok "jq installed"
}

install_tool_mtr() {
  apt-get install -y -qq mtr
  ok "mtr installed"
}

install_tool_ncdu() {
  apt-get install -y -qq ncdu
  ok "ncdu installed"
}

install_tool_parted() {
  apt-get install -y -qq parted util-linux
  ok "parted, lsblk, findmnt installed"
}

install_tool_fish() {
  if ! grep -q "ppa:fish-shell/release-3" /etc/apt/sources.list.d/*.list 2>/dev/null; then
    apt-get install -y -qq software-properties-common
    add-apt-repository -y ppa:fish-shell/release-3
    apt-get update -qq
  fi
  apt-get install -y -qq fish
  ok "fish installed"
}

install_tool_starship() {
  curl -sS https://starship.rs/install.sh | sh -s -- --yes
  ok "starship installed"
}

install_tool_lazygit() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local download_url
  download_url="$(curl -fsSL \
    "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'Linux_x86_64.tar.gz' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/' \
    | tr -d '"')"
  curl -fsSL "$download_url" | tar -xz -C "$tmp_dir"
  mv "$tmp_dir/lazygit" /usr/local/bin/lazygit
  chmod +x /usr/local/bin/lazygit
  rm -rf "$tmp_dir"
  ok "lazygit installed"
}

install_tool_lazydocker() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local download_url
  download_url="$(curl -fsSL \
    "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'Linux_x86_64.tar.gz' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/' \
    | tr -d '"')"
  curl -fsSL "$download_url" | tar -xz -C "$tmp_dir"
  mv "$tmp_dir/lazydocker" /usr/local/bin/lazydocker
  chmod +x /usr/local/bin/lazydocker
  rm -rf "$tmp_dir"
  ok "lazydocker installed"
}

install_tool_gh() {
  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
  fi
  apt-get install -y -qq gh
  ok "gh installed"
}

install_tool_nvim() {
  local nvim_bin_dir="/opt/homekase/nvim-bin"
  local nvim_config_dir="/opt/homekase/nvim-config"

  # Download latest nvim release
  local download_url
  download_url="$(curl -fsSL \
    "https://api.github.com/repos/neovim/neovim/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'nvim-linux-x86_64.tar.gz' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/' \
    | tr -d '"')"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -fsSL "$download_url" | tar -xz -C "$tmp_dir"
  rm -rf "$nvim_bin_dir"
  mv "$tmp_dir"/nvim-linux-x86_64 "$nvim_bin_dir"
  rm -rf "$tmp_dir"
  ln -sf "$nvim_bin_dir/bin/nvim" /usr/local/bin/nvim
  ok "neovim installed at $nvim_bin_dir"

  # Clone LazyVim starter (skip if already exists)
  if [[ ! -d "$nvim_config_dir" ]]; then
    git clone https://github.com/LazyVim/starter "$nvim_config_dir"
    rm -rf "$nvim_config_dir/.git"
  fi
  ok "LazyVim config at $nvim_config_dir"

  # Symlink for SUDO_USER (the user who ran sudo)
  if [[ -n "${SUDO_USER:-}" ]]; then
    local user_home
    user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    mkdir -p "$user_home/.config"
    ln -sfn "$nvim_config_dir" "$user_home/.config/nvim"
    chown -R "$SUDO_USER:$SUDO_USER" "$user_home/.config/nvim"
    ok "~/.config/nvim -> $nvim_config_dir (for $SUDO_USER)"
  fi

  # Symlink for root
  mkdir -p /root/.config
  ln -sfn "$nvim_config_dir" /root/.config/nvim
  ok "/root/.config/nvim -> $nvim_config_dir"
}

# ---------------------------------------------------------------------------
# Fish system config writer
# ---------------------------------------------------------------------------
_write_fish_config() {
  local fish_conf_dir="/etc/fish/conf.d"
  local fish_conf_file="$fish_conf_dir/homekase.fish"
  mkdir -p "$fish_conf_dir"
  cat > "$fish_conf_file" << 'FISH_CONFIG'
# managed by homekase — do not edit
set -x EDITOR nvim
set -x VISUAL nvim

if command -q starship
    starship init fish | source
end

if command -q lazygit
    abbr --add lg lazygit
end

if command -q lazydocker
    abbr --add ld lazydocker
end
FISH_CONFIG
  ok "fish config written to $fish_conf_file"
}
```

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n lib/init.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Verify shellcheck**

```bash
shellcheck -x lib/init.sh
```

Expected: no warnings. If SC2034 fires on unused variables in the metadata loop, add `# shellcheck disable=SC2034` inline on the offending assignment.

- [ ] **Step 4: Smoke-test dispatch (no root needed for syntax)**

```bash
bash -c 'source lib/common.sh; source lib/init.sh; declare -F | grep install_tool'
```

Expected output (15 lines, one per tool):

```
declare -f install_tool_bat
declare -f install_tool_btop
declare -f install_tool_fzf
declare -f install_tool_gh
declare -f install_tool_git
declare -f install_tool_jq
declare -f install_tool_lazydocker
declare -f install_tool_lazygit
declare -f install_tool_mtr
declare -f install_tool_ncdu
declare -f install_tool_nvim
declare -f install_tool_parted
declare -f install_tool_ripgrep
declare -f install_tool_starship
declare -f install_tool_fish
```

- [ ] **Step 5: Commit**

```bash
git add lib/init.sh
git commit -m "feat: implement homekase init with gum multi-select and per-tool install functions"
```

---

### Task 3: tests/test_init.bats — TDD

Write tests first, then verify they pass against the implementation from Task 2.

**Files:**
- Create: `tests/test_init.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/test_init.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/init.sh"
}

# ---------------------------------------------------------------------------
# Sanity: is_installed works inside init context
# ---------------------------------------------------------------------------

@test "is_installed returns 0 for bash (sanity)" {
  run is_installed bash
  [ "$status" -eq 0 ]
}

@test "is_installed returns 1 for nonexistent binary" {
  run is_installed __no_such_binary_xyz__
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _tool_binary helper
# ---------------------------------------------------------------------------

@test "_tool_binary returns rg for ripgrep" {
  run _tool_binary ripgrep
  [ "$status" -eq 0 ]
  [ "$output" = "rg" ]
}

@test "_tool_binary returns parted for parted" {
  run _tool_binary parted
  [ "$status" -eq 0 ]
  [ "$output" = "parted" ]
}

@test "_tool_binary returns nvim for nvim" {
  run _tool_binary nvim
  [ "$status" -eq 0 ]
  [ "$output" = "nvim" ]
}

@test "_tool_binary returns key unchanged for git" {
  run _tool_binary git
  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

@test "_tool_binary returns key unchanged for fzf" {
  run _tool_binary fzf
  [ "$status" -eq 0 ]
  [ "$output" = "fzf" ]
}

# ---------------------------------------------------------------------------
# _write_fish_config writes expected content
# ---------------------------------------------------------------------------

@test "_write_fish_config writes homekase.fish with correct content" {
  local tmp_etc
  tmp_etc="$(mktemp -d)"
  # Override the hardcoded path by monkey-patching the function
  _write_fish_config_test() {
    local fish_conf_dir="$tmp_etc/fish/conf.d"
    local fish_conf_file="$fish_conf_dir/homekase.fish"
    mkdir -p "$fish_conf_dir"
    cat > "$fish_conf_file" << 'FISH_CONFIG'
# managed by homekase — do not edit
set -x EDITOR nvim
set -x VISUAL nvim

if command -q starship
    starship init fish | source
end

if command -q lazygit
    abbr --add lg lazygit
end

if command -q lazydocker
    abbr --add ld lazydocker
end
FISH_CONFIG
    echo "$fish_conf_file"
  }
  local out_path
  out_path="$(_write_fish_config_test)"
  [ -f "$out_path" ]
  grep -q "set -x EDITOR nvim"      "$out_path"
  grep -q "set -x VISUAL nvim"      "$out_path"
  grep -q "starship init fish"       "$out_path"
  grep -q "abbr --add lg lazygit"    "$out_path"
  grep -q "abbr --add ld lazydocker" "$out_path"
  grep -q "managed by homekase"      "$out_path"
  rm -rf "$tmp_etc"
}

@test "_write_fish_config creates parent directory if missing" {
  local tmp_etc
  tmp_etc="$(mktemp -d)"
  local fish_conf_dir="$tmp_etc/fish/conf.d"
  [ ! -d "$fish_conf_dir" ]
  mkdir -p "$fish_conf_dir"
  touch "$fish_conf_dir/homekase.fish"
  [ -f "$fish_conf_dir/homekase.fish" ]
  rm -rf "$tmp_etc"
}

# ---------------------------------------------------------------------------
# _TOOLS metadata structure
# ---------------------------------------------------------------------------

@test "_TOOLS array is non-empty" {
  [ "${#_TOOLS[@]}" -gt 0 ]
}

@test "_TOOLS has 15 entries" {
  [ "${#_TOOLS[@]}" -eq 15 ]
}

@test "_TOOLS git entry is pre-selected" {
  local found=false
  for entry in "${_TOOLS[@]}"; do
    local key default_sel
    IFS='|' read -r key _ _ default_sel <<< "$entry"
    if [[ "$key" == "git" && "$default_sel" == "yes" ]]; then
      found=true
    fi
  done
  $found
}

@test "_TOOLS fish entry is not pre-selected" {
  local found=false
  for entry in "${_TOOLS[@]}"; do
    local key default_sel
    IFS='|' read -r key _ _ default_sel <<< "$entry"
    if [[ "$key" == "fish" && "$default_sel" == "no" ]]; then
      found=true
    fi
  done
  $found
}

@test "_TOOLS nvim entry is not pre-selected" {
  local found=false
  for entry in "${_TOOLS[@]}"; do
    local key default_sel
    IFS='|' read -r key _ _ default_sel <<< "$entry"
    if [[ "$key" == "nvim" && "$default_sel" == "no" ]]; then
      found=true
    fi
  done
  $found
}

# ---------------------------------------------------------------------------
# cmd_init requires root
# ---------------------------------------------------------------------------

@test "cmd_init exits 1 when not root" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/init.sh'
    EUID=1000 cmd_init
  "
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# All install_tool_* functions are defined
# ---------------------------------------------------------------------------

@test "install_tool_git is defined" {
  declare -f install_tool_git > /dev/null
}

@test "install_tool_fzf is defined" {
  declare -f install_tool_fzf > /dev/null
}

@test "install_tool_bat is defined" {
  declare -f install_tool_bat > /dev/null
}

@test "install_tool_ripgrep is defined" {
  declare -f install_tool_ripgrep > /dev/null
}

@test "install_tool_btop is defined" {
  declare -f install_tool_btop > /dev/null
}

@test "install_tool_jq is defined" {
  declare -f install_tool_jq > /dev/null
}

@test "install_tool_mtr is defined" {
  declare -f install_tool_mtr > /dev/null
}

@test "install_tool_ncdu is defined" {
  declare -f install_tool_ncdu > /dev/null
}

@test "install_tool_parted is defined" {
  declare -f install_tool_parted > /dev/null
}

@test "install_tool_fish is defined" {
  declare -f install_tool_fish > /dev/null
}

@test "install_tool_starship is defined" {
  declare -f install_tool_starship > /dev/null
}

@test "install_tool_lazygit is defined" {
  declare -f install_tool_lazygit > /dev/null
}

@test "install_tool_lazydocker is defined" {
  declare -f install_tool_lazydocker > /dev/null
}

@test "install_tool_gh is defined" {
  declare -f install_tool_gh > /dev/null
}

@test "install_tool_nvim is defined" {
  declare -f install_tool_nvim > /dev/null
}
```

- [ ] **Step 2: Run tests — expect failure (before Task 2 is done) or pass (if Task 2 was done first)**

```bash
bats tests/test_init.bats
```

Expected when run after Task 2: all 30 tests pass.

If run before Task 2: tests fail with `lib/init.sh: No such file`. That is correct — complete Task 2 first.

- [ ] **Step 3: Run full test suite**

```bash
make test
```

Expected output:

```
:: Bats syntax...
  ✓ tests/test_common.bats
  ✓ tests/test_config.bats
  ✓ tests/test_dispatch.bats
  ✓ tests/test_init.bats
:: Bats unit tests...
...
X tests, 0 failures
```

- [ ] **Step 4: Run shellcheck on new file**

```bash
make lint
```

Expected: no new failures.

- [ ] **Step 5: Commit**

```bash
git add tests/test_init.bats
git commit -m "test: add test_init.bats covering tool metadata, fish config, and cmd_init guard"
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|-------------|------|
| gum installed in `install.sh` before git clone | Task 1 |
| `cmd_init` calls `require_root` | Task 2 — first line of `cmd_init` |
| gum multi-select with all 15 tools | Task 2 — `gum_items` loop + `gum choose --no-limit` |
| Pre-selected tools checked by default | Task 2 — `--selected=` flags per `default_sel == "yes"` |
| `(installed)` / `(not installed)` label in menu | Task 2 — `status_label` from `command -v` check |
| Each tool has its own `install_tool_<key>` | Task 2 — 15 functions |
| `install_tool_git` — apt | Task 2 |
| `install_tool_fzf` — apt | Task 2 |
| `install_tool_bat` — apt | Task 2 |
| `install_tool_ripgrep` — apt | Task 2 |
| `install_tool_btop` — apt | Task 2 |
| `install_tool_jq` — apt | Task 2 |
| `install_tool_mtr` — apt | Task 2 |
| `install_tool_ncdu` — apt | Task 2 |
| `install_tool_parted` — apt (parted util-linux) | Task 2 |
| `install_tool_fish` — add ppa, apt | Task 2 |
| `install_tool_starship` — curl install.sh | Task 2 |
| `install_tool_lazygit` — GitHub Releases latest, linux_x86_64 | Task 2 |
| `install_tool_lazydocker` — GitHub Releases latest, linux_x86_64 | Task 2 |
| `install_tool_gh` — GitHub CLI apt repo | Task 2 |
| `install_tool_nvim` — GitHub Releases + LazyVim clone + symlinks for SUDO_USER and root | Task 2 |
| Fish config at `/etc/fish/conf.d/homekase.fish` when fish selected | Task 2 — `_write_fish_config` called from `cmd_init` |
| Fish config contains `EDITOR=nvim`, `VISUAL=nvim` | Task 2 — heredoc in `_write_fish_config` |
| Fish config contains `starship init fish \| source` guarded by `command -q starship` | Task 2 — heredoc |
| Fish config contains `abbr --add lg lazygit` guarded by `command -q lazygit` | Task 2 — heredoc |
| Fish config contains `abbr --add ld lazydocker` guarded by `command -q lazydocker` | Task 2 — heredoc |
| `ok "init complete"` at end | Task 2 — last line of `cmd_init` |
| `is_installed bash` sanity test | Task 3 |
| Fish config test | Task 3 — `_write_fish_config_test` helper writes to tmpdir |
| `cmd_init` root guard test | Task 3 |
| Tests for pre-selected / optional metadata | Task 3 |

### Placeholder scan

None found. Every step has:
- Real bash code with no TODOs
- Exact `run` commands with expected output
- Exact `git commit` messages

### Type consistency

- `_tool_binary` defined in Task 2, called in `cmd_init` (same file) and in Task 3 tests — consistent name.
- `_write_fish_config` defined in Task 2, called from `cmd_init` in same file, tested via inline helper in Task 3 — consistent.
- `install_tool_<key>` pattern: 15 functions defined, all called by `"install_tool_${key}"` dispatch in `cmd_init`. Task 3 tests verify all 15 exist via `declare -f`.
- `_TOOLS` array: defined as `_TOOLS`, referenced as `"${_TOOLS[@]}"` — consistent.
- `require_root` from `lib/common.sh` — already exists, signature unchanged, used identically to other commands.
- `header`, `info`, `ok`, `warn` from `lib/common.sh` — all used exactly as defined.
