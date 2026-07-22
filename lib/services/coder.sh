#!/usr/bin/env bash
# shellcheck disable=SC2154  # HOMEKASE_CONFIG set by sourcing script
# Coder service installer — llama.cpp + Qwen2.5-Coder-7B-Instruct Q4_K_M

_CODER_HF_REPO="bartowski/Qwen2.5-Coder-7B-Instruct-GGUF"
_CODER_MODEL_FILE="Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"
_CODER_MODEL_SIZE_GB=4.4

# --- Helpers ---------------------------------------------------------------

_download_coder_model() {
  local model_dir="$1"
  local url="https://huggingface.co/${_CODER_HF_REPO}/resolve/main/${_CODER_MODEL_FILE}"
  local dest="${model_dir}/${_CODER_MODEL_FILE}"

  if [[ -f "${dest}" ]]; then
    ok "Model already present: ${dest}"
    return 0
  fi

  info "Model: ${_CODER_MODEL_FILE} (~${_CODER_MODEL_SIZE_GB}GB)"
  info "Source: ${url}"

  mkdir -p "${model_dir}"

  if ! ask_confirm "Download model to ${model_dir}?"; then
    return 1
  fi

  info "Downloading..."
  if curl -fSL --retry 3 --retry-delay 5 \
    --progress-bar \
    -o "${dest}" "${url}"; then
    ok "Model downloaded to ${dest}"
    return 0
  else
    error "Download failed."
    rm -f "${dest}"
    return 1
  fi
}

# --- Deploy ----------------------------------------------------------------

deploy_coder() {
  require_root
  header "Installing Coder LLM Service (llama.cpp + Qwen2.5-Coder)"

  local CODER_DIR="${HOMEKASE_REPO_DIR}/services/coder"

  # --- Data directory ---
  local DATA_DIR
  DATA_DIR="$(ask_input "Data directory" "/data/coder")"

  local MODEL_DIR="${DATA_DIR}/models"
  local CONFIG_DIR="${DATA_DIR}/config"
  mkdir -p "${MODEL_DIR}" "${CONFIG_DIR}"

  # --- Port ---
  local PORT TS BIND_ADDR
  PORT="$(port_wizard "coder" 1)"
  TS="$(tailscale_serve_setup "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  # --- Threads ---
  local nproc_val
  nproc_val="$(nproc 2>/dev/null || echo 4)"
  local default_threads=$(( nproc_val / 2 ))
  (( default_threads < 1 )) && default_threads=1
  info "System has ${nproc_val} CPU threads available."
  local THREADS
  THREADS="$(ask_input "Threads for inference" "${default_threads}")"

  # --- Parallel slots ---
  info "Parallel slots = number of concurrent requests the server handles."
  info "Each slot uses ~${_CODER_MODEL_SIZE_GB}GB RAM for KV cache."
  info "2 slots is enough for interactive coding use."
  local PARALLEL
  PARALLEL="$(ask_input "Parallel slots" "2")"

  # --- Context size ---
  info "Context size = max tokens the model can see at once."
  info "Larger context uses more RAM (~1.5GB per 8192 tokens)."
  info "8192 is good for most coding tasks. 16384 for larger files."
  local CTX
  CTX="$(ask_input "Context size (tokens)" "8192")"

  # --- RAM limit ---
  local ram_needed
  ram_needed="$(awk "BEGIN {printf \"%.0f\", ${_CODER_MODEL_SIZE_GB} + (${CTX}/8192)*1.5 + 2}")"
  info "Estimated RAM needed: ~${ram_needed}GB (model + KV cache + overhead)."
  local RAM_LIMIT
  RAM_LIMIT="$(ask_input "RAM limit (e.g. 8g)" "${ram_needed}g")"

  # --- API key ---
  local API_KEY
  API_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64)"

  # --- Download model ---
  if ! _download_coder_model "${MODEL_DIR}"; then
    info "Cancelled."
    return 0
  fi

  # --- Write .env ---
  mkdir -p "${HOMELAB_DIR}/coder"
  write_env_file "coder" "PORT=${PORT}
BIND_ADDR=${BIND_ADDR}
MODEL_DIR=${MODEL_DIR}
MODEL_FILE=${_CODER_MODEL_FILE}
CTX=${CTX}
THREADS=${THREADS}
PARALLEL=${PARALLEL}
RAM_LIMIT=${RAM_LIMIT}
API_KEY=${API_KEY}
TS=${TS}"

  # --- Generate opencode config ---
  local SERVICE_URL
  SERVICE_URL="$(service_url "${PORT}")"

  cat > "${CONFIG_DIR}/opencode.json" <<EOCONFIG
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "coder": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Qwen2.5-Coder (local)",
      "options": {
        "baseURL": "${SERVICE_URL}/v1",
        "apiKey": "${API_KEY}"
      },
      "models": {
        "qwen2.5-coder-7b": {
          "name": "Qwen2.5-Coder 7B Q4_K_M",
          "limit": {
            "context": ${CTX},
            "output": 4096
          }
        }
      }
    }
  },
  "model": "coder/qwen2.5-coder-7b",
  "enabled_providers": ["coder"]
}
EOCONFIG

  # --- Start ---
  info "Pulling latest llama.cpp server image..."
  docker compose -f "${CODER_DIR}/docker-compose.yml" \
    --env-file "${DATA_DIR}/.env" pull

  info "Starting coder..."
  docker compose -f "${CODER_DIR}/docker-compose.yml" \
    --env-file "${DATA_DIR}/.env" up -d

  ok "Coder is running on port ${PORT}"
  echo
  info "API endpoint: ${SERVICE_URL}/v1"
  info "Health check: ${SERVICE_URL}/health"
  info "Config file: ${CONFIG_DIR}/opencode.json"
  echo
  info "To use with OpenCode, copy the config to your project:"
  info "  cp ${CONFIG_DIR}/opencode.json .opencode.json"
}

# --- Update ----------------------------------------------------------------

_update_coder() {
  require_root
  header "Updating Coder"

  local CODER_DIR="${HOMEKASE_REPO_DIR}/services/coder"
  local DATA_DIR="${HOMELAB_DIR}/coder"

  if [[ ! -f "${DATA_DIR}/.env" ]]; then
    error "No .env found at ${DATA_DIR}. Deploy first."
    return 1
  fi

  info "Pulling latest llama.cpp server image..."
  docker compose -f "${CODER_DIR}/docker-compose.yml" \
    --env-file "${DATA_DIR}/.env" pull

  info "Recreating container..."
  docker compose -f "${CODER_DIR}/docker-compose.yml" \
    --env-file "${DATA_DIR}/.env" up -d

  ok "Coder updated."
}

# --- Remove ----------------------------------------------------------------

remove_coder() {
  require_root
  header "Removing Coder"

  local CODER_DIR="${HOMEKASE_REPO_DIR}/services/coder"
  local DATA_DIR="${HOMELAB_DIR}/coder"

  if [[ -f "${DATA_DIR}/.env" ]]; then
    local PORT
    PORT="$(config_get 'apps.coder.port' 2>/dev/null || grep '^PORT=' "${DATA_DIR}/.env" | cut -d= -f2)"

    info "Stopping coder..."
    docker compose -f "${CODER_DIR}/docker-compose.yml" \
      --env-file "${DATA_DIR}/.env" down --remove-orphans 2>/dev/null || true

    if [[ -n "${PORT}" ]]; then
      tailscale_serve_remove "${PORT}"
    fi

    config_remove 'apps.coder'
    ok "Coder stopped."
  else
    warn "No .env found — container may already be removed."
  fi
}
