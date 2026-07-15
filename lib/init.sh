#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Tool metadata: key|display_name|description|default_selected
# default_selected: "yes" = pre-checked, "no" = unchecked
# ---------------------------------------------------------------------------
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

# Primary binary to check for each tool key
_tool_binary() {
  case "$1" in
    ripgrep)    echo "rg" ;;
    parted)     echo "parted" ;;
    nvim)       echo "nvim" ;;
    lazygit)    echo "lazygit" ;;
    lazydocker) echo "lazydocker" ;;
    starship)   echo "starship" ;;
    *)          echo "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_init
# ---------------------------------------------------------------------------
cmd_init() {
  require_root

  local -a gum_items=()
  local -a default_keys=()
  for entry in "${_TOOLS[@]}"; do
    local key name desc default_sel
    IFS='|' read -r key name desc default_sel <<< "${entry}"
    local binary
    binary="$(_tool_binary "${key}")"
    local status_label
    if command -v "${binary}" &>/dev/null; then
      status_label="(installed)"
    else
      status_label="(not installed)"
    fi
    gum_items+=("[${key}] ${name} — ${desc} ${status_label}")
    if [[ "${default_sel}" == "yes" ]]; then
      default_keys+=("[${key}] ${name} — ${desc} ${status_label}")
    fi
  done

  local -a selected_flags=()
  for item in "${default_keys[@]}"; do
    selected_flags+=(--selected="${item}")
  done

  header "homekase init — select tools to install"

  local chosen
  chosen="$(printf '%s\n' "${gum_items[@]}" | \
    gum choose --no-limit \
      --header "Space to toggle, Enter to confirm" \
      "${selected_flags[@]}")" || true

  if [[ -z "${chosen}" ]]; then
    info "Nothing selected. Exiting."
    return 0
  fi

  local -a selected_keys=()
  while IFS= read -r line; do
    local k
    k="${line#\[}"
    k="${k%%\]*}"
    selected_keys+=("${k}")
  done <<< "${chosen}"

  local key
  for key in "${selected_keys[@]}"; do
    info "Installing: ${key}..."
    "install_tool_${key}"
  done

  local fish_selected=false
  for key in "${selected_keys[@]}"; do
    [[ "${key}" == "fish" ]] && fish_selected=true
  done

  if ${fish_selected}; then
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
  apt-get install -y -qq fish
  ok "fish installed"
}

install_tool_starship() {
  # shellcheck disable=SC2312
  curl -sS https://starship.rs/install.sh | sh -s -- --yes
  ok "starship installed"
}

install_tool_lazygit() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local download_url
  # shellcheck disable=SC2312
  download_url="$(curl -fsSL \
    "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'Linux_x86_64.tar.gz' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/' \
    | tr -d '"')"
  # shellcheck disable=SC2312
  curl -fsSL "${download_url}" | tar -xz -C "${tmp_dir}"
  mv "${tmp_dir}/lazygit" /usr/local/bin/lazygit
  chmod +x /usr/local/bin/lazygit
  rm -rf "${tmp_dir}"
  ok "lazygit installed"
}

install_tool_lazydocker() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local download_url
  # shellcheck disable=SC2312
  download_url="$(curl -fsSL \
    "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'Linux_x86_64.tar.gz' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/' \
    | tr -d '"')"
  # shellcheck disable=SC2312
  curl -fsSL "${download_url}" | tar -xz -C "${tmp_dir}"
  mv "${tmp_dir}/lazydocker" /usr/local/bin/lazydocker
  chmod +x /usr/local/bin/lazydocker
  rm -rf "${tmp_dir}"
  ok "lazydocker installed"
}

install_tool_gh() {
  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    # shellcheck disable=SC2312
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    arch="$(dpkg --print-architecture)"
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
  fi
  apt-get install -y -qq gh
  ok "gh installed"
}

install_tool_nvim() {
  apt-get install -y -qq build-essential
  local nvim_bin_dir="/opt/homekase/nvim-bin"
  local nvim_config_dir="/opt/homekase/nvim-config"

  local download_url
  # shellcheck disable=SC2312
  download_url="$(curl -fsSL \
    "https://api.github.com/repos/neovim/neovim/releases/latest" \
    | grep '"browser_download_url"' \
    | grep 'nvim-linux-x86_64.tar.gz' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/' \
    | tr -d '"')"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2312
  curl -fsSL "${download_url}" | tar -xz -C "${tmp_dir}"
  rm -rf "${nvim_bin_dir}"
  mv "${tmp_dir}/nvim-linux-x86_64" "${nvim_bin_dir}"
  rm -rf "${tmp_dir}"
  ln -sf "${nvim_bin_dir}/bin/nvim" /usr/local/bin/nvim
  ok "neovim installed at ${nvim_bin_dir}"

  if [[ ! -d "${nvim_config_dir}" ]]; then
    git clone https://github.com/LazyVim/starter "${nvim_config_dir}"
    rm -rf "${nvim_config_dir}/.git"
  fi
  ok "LazyVim config at ${nvim_config_dir}"

  if [[ -n "${SUDO_USER:-}" ]]; then
    local user_home
    # shellcheck disable=SC2312
    user_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    mkdir -p "${user_home}/.config"
    ln -sfn "${nvim_config_dir}" "${user_home}/.config/nvim"
    chown -R "${SUDO_USER}:${SUDO_USER}" "${user_home}/.config/nvim"
    ok "${user_home}/.config/nvim -> ${nvim_config_dir} (for ${SUDO_USER})"
  fi

  mkdir -p /root/.config
  ln -sfn "${nvim_config_dir}" /root/.config/nvim
  ok "/root/.config/nvim -> ${nvim_config_dir}"
}

# ---------------------------------------------------------------------------
# Fish system config writer
# ---------------------------------------------------------------------------
_write_fish_config() {
  local fish_conf_dir="/etc/fish/conf.d"
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
  ok "fish config written to ${fish_conf_file}"
}
