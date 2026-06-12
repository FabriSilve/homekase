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
  local uid
  uid="$(id -u)"
  if [[ "${EUID:-${uid}}" -ne 0 ]]; then
    exec sudo "${HOMEKASE_ORIG_CMD[@]}"
  fi
}

ask_confirm() {
  local question="${1:-Are you sure?}"
  if gum_available; then
    gum confirm "${question}"
  else
    read -r -p "${question} [y/N] " reply
    [[ "${reply,,}" == "y" ]]
  fi
}

ask_input() {
  local prompt="$1" default="${2:-}"
  if gum_available; then
    gum input --placeholder "${prompt}" --value "${default}"
  else
    read -r -p "${prompt} [${default}]: " reply
    echo "${reply:-${default}}"
  fi
}

ask_choose() {
  local prompt="$1"; shift
  if gum_available; then
    printf '%s\n' "$@" | gum choose --header "${prompt}"
  else
    echo "${prompt}"
    local i=1
    for opt in "$@"; do echo "  ${i}) ${opt}"; ((i++)); done
    read -r -p "Choice [1]: " reply
    local idx=$(( ${reply:-1} - 1 ))
    local opts=("$@")
    echo "${opts[${idx}]}"
  fi
}
