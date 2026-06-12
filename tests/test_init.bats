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
  _write_fish_config_test() {
    local fish_conf_dir="${tmp_etc}/fish/conf.d"
    local fish_conf_file="${fish_conf_dir}/homekase.fish"
    mkdir -p "${fish_conf_dir}"
    cat > "${fish_conf_file}" << 'FISH_CONFIG'
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
    echo "${fish_conf_file}"
  }
  local out_path
  out_path="$(_write_fish_config_test)"
  [ -f "${out_path}" ]
  grep -q "set -x EDITOR nvim"      "${out_path}"
  grep -q "set -x VISUAL nvim"      "${out_path}"
  grep -q "starship init fish"       "${out_path}"
  grep -q "abbr --add lg lazygit"    "${out_path}"
  grep -q "abbr --add ld lazydocker" "${out_path}"
  grep -q "managed by homekase"      "${out_path}"
  rm -rf "${tmp_etc}"
}

@test "_write_fish_config creates parent directory if missing" {
  local tmp_etc
  tmp_etc="$(mktemp -d)"
  local fish_conf_dir="${tmp_etc}/fish/conf.d"
  [ ! -d "${fish_conf_dir}" ]
  mkdir -p "${fish_conf_dir}"
  touch "${fish_conf_dir}/homekase.fish"
  [ -f "${fish_conf_dir}/homekase.fish" ]
  rm -rf "${tmp_etc}"
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
    IFS='|' read -r key _ _ default_sel <<< "${entry}"
    if [[ "${key}" == "git" && "${default_sel}" == "yes" ]]; then
      found=true
    fi
  done
  ${found}
}

@test "_TOOLS fish entry is not pre-selected" {
  local found=false
  for entry in "${_TOOLS[@]}"; do
    local key default_sel
    IFS='|' read -r key _ _ default_sel <<< "${entry}"
    if [[ "${key}" == "fish" && "${default_sel}" == "no" ]]; then
      found=true
    fi
  done
  ${found}
}

@test "_TOOLS nvim entry is not pre-selected" {
  local found=false
  for entry in "${_TOOLS[@]}"; do
    local key default_sel
    IFS='|' read -r key _ _ default_sel <<< "${entry}"
    if [[ "${key}" == "nvim" && "${default_sel}" == "no" ]]; then
      found=true
    fi
  done
  ${found}
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
