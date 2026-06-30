#!/usr/bin/env bash
# Local AI assistant service installer.
# Sourced by lib/services/service.sh on `homekase add assistant`.
# Deploys from services/assistant/ within the homekase repo.

deploy_assistant() {
  require_root
  header "Installing Local AI Assistant"

  local ram_mb model
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

  local PORT TS BIND_ADDR ASSISTANT_URL
  PORT="$(port_wizard "assistant" 1)"
  TS="$(tailscale_serve_setup "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"
  ASSISTANT_URL="$(service_url "${PORT}")"

  local ASSISTANT_DIR="${HOMEKASE_REPO_DIR}/services/assistant"
  local DEPLOY_DIR="${HOMELAB_DIR}/assistant"

  mkdir -p "${DEPLOY_DIR}"

  write_env_file "assistant" "PORT=${PORT}
OLLAMA_MODEL=${model}
OLLAMA_MEM_LIMIT=12g
OLLAMA_CPU_LIMIT=4
OLLAMA_MEM_RESERVATION=4g
SEARXNG_SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || echo 'changeme')
TS=${TS}
BIND_ADDR=${BIND_ADDR}
ASSISTANT_URL=${ASSISTANT_URL}"

  info "Building agent image (this may take a few minutes)..."
  docker compose -f "${ASSISTANT_DIR}/docker-compose.yml" build

  info "Starting assistant..."
  docker compose -f "${ASSISTANT_DIR}/docker-compose.yml" up -d

  info "Pulling Ollama model ${model} (large download — be patient)..."
  docker exec assistant-ollama ollama pull "${model}" 2>/dev/null || \
    docker exec ollama ollama pull "${model}"

  config_app_set assistant installed true
  config_app_set assistant port      "${PORT}"
  config_app_set assistant tailscale "${TS}"

  ok "Assistant running on port ${PORT}  →  ${ASSISTANT_URL}"
  info "Model: ${model}"
  info "Open WebUI: ${ASSISTANT_URL}"
}

remove_assistant() {
  require_root
  header "Removing Local AI Assistant"
  local port
  port="$(config_app_get assistant port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"

  local ASSISTANT_DIR="${HOMEKASE_REPO_DIR}/services/assistant"
  if [[ -f "${ASSISTANT_DIR}/docker-compose.yml" ]]; then
    docker compose -f "${ASSISTANT_DIR}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
  fi

  remove_service_dir "assistant"
  config_app_remove assistant
  ok "Assistant removed."
}
