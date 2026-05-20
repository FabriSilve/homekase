#!/bin/bash
# common_wizard.sh — gum-based UI overrides
# Sourced AFTER common.sh to override functions with gum equivalents.
# Requires: gum installed and available in PATH.

header() {
  echo ""
  gum style \
    --border rounded \
    --border-foreground 212 \
    --padding "0 2" \
    --bold \
    "$1"
  echo ""
}

section() {
  local title="$1"
  local description="$2"
  echo ""
  gum style \
    --border rounded \
    --border-foreground 212 \
    --padding "1 2" \
    --bold \
    "${title}" \
    "" \
    "${description}"
  echo ""
}

info() {
  gum style --foreground 39 ":: $1"
}

ok() {
  gum style --foreground 76 "✓ $1"
}

warn() {
  gum style --foreground 214 "! $1"
}

error() {
  gum style --foreground 196 "✗ $1"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  if [[ "${default}" = "y" ]]; then
    gum confirm --default=yes "${prompt}"
  else
    gum confirm --default=no "${prompt}"
  fi
}

prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  if [[ -n "${default}" ]]; then
    gum input --prompt "${prompt}: " --placeholder "${default}" --value "${default}"
  else
    gum input --prompt "${prompt}: "
  fi
}

prompt_secret() {
  local prompt="$1"
  gum input --password --prompt "${prompt}: "
}

prompt_choose() {
  local prompt="$1"
  shift
  gum choose --header "${prompt}" "$@"
}

prompt_multi_choose() {
  local prompt="$1"
  shift
  gum choose --no-limit --header "${prompt}" "$@"
}

run_with_spinner() {
  local msg="$1"
  shift
  gum spin --title "${msg}" -- "$@"
}
