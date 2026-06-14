#!/usr/bin/env bash
# Local AI assistant service installer.
# Sourced by lib/services/service.sh on `homekase add assistant`.
# Clones git@github.com:FabriSilve/server-assistant.git, selects an Ollama
# model based on available RAM, then builds + starts via docker compose.

deploy_assistant() {
  require_root
  header "Installing Local AI Assistant"

  local ram_mb model
  # shellcheck disable=SC2312
  ram_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
  if [[ -z "${ram_mb}" ]]; then
    error "Cannot read available RAM (is 'free' installed?)"
    exit 1
  fi

  if   (( ram_mb >= 12288 )); then model="qwen2.5:14b"
  elif (( ram_mb >= 7168  )); then model="qwen2.5:7b"
  elif (( ram_mb >= 4096  )); then model="qwen2.5:3b"
  else
    error "Insufficient RAM for assistant (detected ${ram_mb}MB, need at least 4096MB)."
    exit 1
  fi
  info "Selected model: ${model}  (detected ${ram_mb}MB RAM)"

  local ssh_key
  ssh_key="$(config_get 'ssh_key' 2>/dev/null || echo '/etc/homekase/.ssh/id_ed25519')"
  local REPO_DIR="${HOMELAB_DIR}/assistant"

  if [[ -d "${REPO_DIR}/.git" ]]; then
    info "Updating server-assistant repo..."
    GIT_SSH_COMMAND="ssh -i ${ssh_key} -o StrictHostKeyChecking=accept-new" \
      git -C "${REPO_DIR}" pull --ff-only
  else
    info "Cloning server-assistant repo..."
    mkdir -p "$(dirname "${REPO_DIR}")"
    GIT_SSH_COMMAND="ssh -i ${ssh_key} -o StrictHostKeyChecking=accept-new" \
      git clone git@github.com:FabriSilve/server-assistant.git "${REPO_DIR}"
  fi

  local PORT TS
  PORT="$(port_wizard "assistant" 1)"
  TS="$(tailscale_serve_setup "${PORT}")"

  write_env_file "assistant" "PORT=${PORT}
OLLAMA_MODEL=${model}
TS=${TS}"

  info "Building assistant image (this may take a few minutes)..."
  docker compose -f "${REPO_DIR}/docker-compose.yml" build

  info "Starting assistant..."
  docker compose -f "${REPO_DIR}/docker-compose.yml" up -d

  info "Pulling Ollama model ${model} (large download — be patient)..."
  docker exec ollama ollama pull "${model}"

  config_app_set assistant installed true
  config_app_set assistant port      "${PORT}"
  config_app_set assistant tailscale "${TS}"

  ok "Assistant running on port ${PORT}  →  http://localhost:${PORT}"
  info "Model: ${model}"
}

remove_assistant() {
  require_root
  header "Removing Local AI Assistant"
  local port
  port="$(config_app_get assistant port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "assistant"
  config_app_remove assistant
  ok "Assistant removed."
}
