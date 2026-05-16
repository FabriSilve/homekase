#!/bin/bash

HOMELAB_DIR="/opt/homelab"
DATA_DIR="/data"
STORAGE_DIR="/storage"
REPO_URL="https://github.com/you/homekase.git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}::${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
header() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}\n"; }

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local answer
  if [ "$default" = "y" ]; then
    prompt="$prompt [Y/n]"
  else
    prompt="$prompt [y/N]"
  fi
  read -r -p "$prompt " answer
  answer=${answer:-$default}
  [[ "$answer" =~ ^[Yy]$ ]]
}

prompt_input() {
  local prompt="$1"
  local default="$2"
  local value
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
  else
    read -r -p "$prompt: " value
    echo "$value"
  fi
}

prompt_secret() {
  local prompt="$1"
  local value
  read -r -s -p "$prompt: " value
  echo
  echo "$value"
}

spinner() {
  local pid=$1
  local msg=$2
  local spin='-\|/'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r${BLUE}::${NC} %s %s" "$msg" "${spin:$i:1}"
    sleep 0.1
  done
  printf "\r${GREEN}✓${NC} %s\n" "$msg"
}

run_with_spinner() {
  local msg="$1"
  shift
  ("$@" > /dev/null 2>&1) &
  local pid=$!
  spinner "$pid" "$msg"
  wait "$pid"
  return $?
}

ensure_sudo() {
  if [ "$EUID" -ne 0 ]; then
    error "Please run with sudo"
    exit 1
  fi
}

ensure_root() {
  if [ "$(whoami)" != "root" ]; then
    error "Please run as root"
    exit 1
  fi
}

is_installed() {
  command -v "$1" >/dev/null 2>&1
}

is_dpkg_installed() {
  dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

dir_exists() {
  [ -d "$1" ]
}

file_exists() {
  [ -f "$1" ]
}

get_user() {
  logname 2>/dev/null || echo "$SUDO_USER" || echo "$USER"
}

get_home() {
  eval echo "~$(get_user)"
}
