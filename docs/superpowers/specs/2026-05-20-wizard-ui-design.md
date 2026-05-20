# Wizard UI Enhancement — Design Spec

## Goal

Add optional gum-based enhanced wizard UI to homekase setup. User chooses at start of setup. Same function interface in both modes — callers never care which backend runs.

## Architecture

```
common.sh            <- base functions (always loaded, works without gum)
common_wizard.sh     <- gum overrides, same function names (loaded conditionally)
```

### Flow in setup.sh

```bash
source lib/common.sh                      # always

# Early prompt (using base prompt_yes_no, gum not installed yet)
if prompt_yes_no "Enable enhanced wizard UI?"; then
  install_gum                             # add Charm apt repo + apt install gum
  source lib/common_wizard.sh             # override functions
fi
```

## Function Interface (both files implement these)

### Existing (override in wizard)

| Function | Signature | Base behavior | Wizard behavior |
|---|---|---|---|
| `header` | `header "title"` | `━━━ Title ━━━` | `gum style --border rounded` |
| `info` | `info "msg"` | `:: msg` (blue) | `gum style` subtle |
| `ok` | `ok "msg"` | `✓ msg` (green) | `gum style` green |
| `warn` | `warn "msg"` | `! msg` (yellow) | `gum style` yellow |
| `error` | `error "msg"` | `✗ msg` (red) | `gum style` red |
| `prompt_yes_no` | `prompt_yes_no "question" [default]` | `read -r` Y/n | `gum confirm` |
| `prompt_input` | `prompt_input "prompt" [default]` | `read -r -p` | `gum input --placeholder` |
| `prompt_secret` | `prompt_secret "prompt"` | `read -r -s` | `gum input --password` |
| `run_with_spinner` | `run_with_spinner "msg" cmd args...` | custom spin loop | `gum spin` |

### New (added to both files)

| Function | Signature | Base behavior | Wizard behavior |
|---|---|---|---|
| `section` | `section "title" "description"` | header + echo description | `gum style --border rounded` box with title + body |
| `prompt_choose` | `prompt_choose "prompt" opt1 opt2...` | numbered list + `read` | `gum choose` arrow keys |
| `prompt_multi_choose` | `prompt_multi_choose "prompt" opt1 opt2...` | numbered list + `read` (comma-separated) | `gum choose --no-limit` checkboxes |

### Return values

- `prompt_yes_no` — exit code 0/1 (no change)
- `prompt_input` / `prompt_secret` — echo to stdout (no change)
- `prompt_choose` — echo selected option to stdout
- `prompt_multi_choose` — echo selected options, newline-separated, to stdout

## gum Installation

Add Charm apt repo (same pattern as GitHub CLI in `tools.sh:29-31`):

```bash
install_gum() {
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    | tee /etc/apt/sources.list.d/charm.list > /dev/null
  apt update -qq
  apt install -y -qq gum
}
```

## What Does NOT Change

- All existing callers (`services.sh`, `disks.sh`, `immich.sh`, etc.) keep calling same functions
- `--dry-run` mode unaffected
- Non-interactive / CI environments: user says "no" to wizard prompt, base mode used

## Files Changed

1. **`lib/common.sh`** — add `section`, `prompt_choose`, `prompt_multi_choose` base implementations
2. **`lib/common_wizard.sh`** — new file, all gum overrides
3. **`setup.sh`** — add wizard prompt + conditional gum install + source

## Out of Scope (later)

- Migrating lazygit/yazi to apt repos
- Rewriting callers to use new `prompt_choose` / `prompt_multi_choose` (separate task)
- TODOs from the todo list (separate work)
