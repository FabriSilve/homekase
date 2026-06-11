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
