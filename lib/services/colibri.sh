#!/usr/bin/env bash
# Colibrí LLM engine service installer.
# Sourced by lib/services/service.sh on `homekase add colibri`.
# Deploys from services/colibri/ within the homekase repo.

COLIBRI_MIN_MODEL_GB=370
COLIBRI_DEFAULT_RAM_GB=20
COLIBRI_DEFAULT_CTX=16384

_COLIBRI_HF_REPO="mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp"
_COLIBRI_HF_BASE="https://huggingface.co/${_COLIBRI_HF_REPO}/resolve/main"

# Download the GLM-5.2 model from HuggingFace into MODEL_DIR.
# Skips files that already exist. Returns 0 on success, 1 on failure.
_download_colibri_model() {
  local MODEL_DIR="$1"

  if [[ -f "${MODEL_DIR}/tokenizer.json" ]]; then
    info "Model already present in ${MODEL_DIR}."
    return 0
  fi

  warn "Model not found. Downloading GLM-5.2 int4 (~370GB)..."
  warn "This will take a while depending on your connection."
  if ! ask_confirm "Download model to ${MODEL_DIR}?"; then
    return 1
  fi

  mkdir -p "${MODEL_DIR}"

  local TOTAL_SHARDS=141
  local TOTAL_MTP=3
  local TOTAL_FILES=$(( TOTAL_SHARDS + TOTAL_MTP + 2 ))
  local DOWNLOADED=0
  local FAILED=0
  local f i

  # --- Required: tokenizer + config ---
  for f in tokenizer.json config.json; do
    if [[ -f "${MODEL_DIR}/${f}" ]]; then
      DOWNLOADED=$(( DOWNLOADED + 1 ))
      continue
    fi
    info "  [${DOWNLOADED}/${TOTAL_FILES}] Downloading ${f}..."
    if curl -fSL --retry 3 --retry-delay 5 -o "${MODEL_DIR}/${f}" "${_COLIBRI_HF_BASE}/${f}"; then
      DOWNLOADED=$(( DOWNLOADED + 1 ))
    else
      warn "  Failed to download ${f}"
      FAILED=$(( FAILED + 1 ))
    fi
  done

  # --- Required: weight shards out-00000 to out-00140 ---
  for i in $(seq 0 140); do
    f="out-$(printf '%05d' "${i}").safetensors"
    if [[ -f "${MODEL_DIR}/${f}" ]]; then
      DOWNLOADED=$(( DOWNLOADED + 1 ))
      continue
    fi
    info "  [${DOWNLOADED}/${TOTAL_FILES}] Downloading ${f}..."
    if curl -fSL --retry 3 --retry-delay 5 -o "${MODEL_DIR}/${f}" "${_COLIBRI_HF_BASE}/${f}"; then
      DOWNLOADED=$(( DOWNLOADED + 1 ))
    else
      warn "  Failed to download ${f}"
      FAILED=$(( FAILED + 1 ))
    fi
  done

  # --- Required: MTP head shards out-mtp-00000 to out-mtp-00002 ---
  for i in $(seq 0 2); do
    f="out-mtp-$(printf '%05d' "${i}").safetensors"
    if [[ -f "${MODEL_DIR}/${f}" ]]; then
      DOWNLOADED=$(( DOWNLOADED + 1 ))
      continue
    fi
    info "  [${DOWNLOADED}/${TOTAL_FILES}] Downloading ${f}..."
    if curl -fSL --retry 3 --retry-delay 5 -o "${MODEL_DIR}/${f}" "${_COLIBRI_HF_BASE}/${f}"; then
      DOWNLOADED=$(( DOWNLOADED + 1 ))
    else
      warn "  Failed to download ${f}"
      FAILED=$(( FAILED + 1 ))
    fi
  done

  # --- Optional: generation and tokenizer config (don't abort) ---
  for f in generation_config.json tokenizer_config.json; do
    [[ -f "${MODEL_DIR}/${f}" ]] && continue
    curl -fSL --retry 3 --retry-delay 5 -o "${MODEL_DIR}/${f}" "${_COLIBRI_HF_BASE}/${f}" 2>/dev/null || true
  done

  # --- Verify ---
  if [[ ! -f "${MODEL_DIR}/tokenizer.json" ]]; then
    error "Model download failed — tokenizer.json missing."
    return 1
  fi

  if (( FAILED > 0 )); then
    warn "  ${FAILED} file(s) failed to download."
    warn "  Run 'homekase update colibri' to retry missing shards."
  fi

  ok "Model downloaded (${DOWNLOADED}/${TOTAL_FILES} files) to ${MODEL_DIR}"
  return 0
}

# Detect if a path is on rotational storage (HDD) or not (SSD/NVMe).
# Prints "ssd" or "hdd" to stdout.
_detect_disk_type() {
  local path="$1"
  local device parent rotational
  device="$(df --output=source "${path}" 2>/dev/null | tail -1)"
  parent="$(lsblk -no pkname "${device}" 2>/dev/null | head -1)"
  if [[ -z "${parent}" ]]; then
    parent="$(basename "${device}" | sed 's/[0-9]*$//' | sed 's/p$//')"
  fi
  rotational="$(cat "/sys/block/${parent}/queue/rotational" 2>/dev/null || echo "1")"
  if [[ "${rotational}" == "0" ]]; then
    echo "ssd"
  else
    echo "hdd"
  fi
}

# Get available disk space in GB for a path.
_avail_gb() {
  df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -d ' G'
}

deploy_colibri() {
  require_root
  header "Installing Colibrí LLM Engine"

  local COLIBRI_DIR="${HOMEKASE_REPO_DIR}/services/colibri"
  local DEPLOY_DIR="${HOMELAB_DIR}/colibri"

  # --- Port ---
  local PORT TS BIND_ADDR
  PORT="$(port_wizard "colibri" 1)"
  TS="$(tailscale_serve_setup "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  # --- Model path ---
  local MODEL_DIR
  MODEL_DIR="$(ask_input "Model directory" "/storage/colibri/model")"

  mkdir -p "${MODEL_DIR}"

  # Disk type detection
  local disk_type
  disk_type="$(_detect_disk_type "${MODEL_DIR}")"
  local DIRECT=0
  if [[ "${disk_type}" == "ssd" ]]; then
    info "NVMe/SSD detected — using O_DIRECT for optimal performance."
    DIRECT=1
  else
    warn "HDD detected — expect slower cold starts."
    warn "The learning cache warms up over time, but initial"
    warn "responses may take longer than on NVMe."
    echo
    if ! ask_confirm "Proceed with HDD storage?"; then
      info "Cancelled."
      return 0
    fi
  fi

  # Free disk space check
  local avail_gb
  avail_gb="$(_avail_gb "${MODEL_DIR}")"
  if [[ -n "${avail_gb}" ]] && (( avail_gb < COLIBRI_MIN_MODEL_GB )); then
    warn "Only ${avail_gb}GB available at ${MODEL_DIR}."
    warn "Colibrí needs ~${COLIBRI_MIN_MODEL_GB}GB for the model."
    if ! ask_confirm "Proceed anyway?"; then
      info "Cancelled."
      return 0
    fi
  fi

  # --- Download model ---
  if ! _download_colibri_model "${MODEL_DIR}"; then
    info "Cancelled."
    return 0
  fi

  # --- Projects path ---
  local PROJECTS_DIR
  PROJECTS_DIR="$(ask_input "Projects directory" "/storage/colibri/projects")"
  mkdir -p "${PROJECTS_DIR}"
  chown "${SUDO_USER}:${SUDO_USER}" "${PROJECTS_DIR}"

  # --- RAM budget ---
  local ram_gb_suggestion free_ram_gb
  free_ram_gb="$(free -g 2>/dev/null | awk '/^Mem:/{printf "%.0f", $7}')"
  if (( free_ram_gb < COLIBRI_DEFAULT_RAM_GB )); then
    ram_gb_suggestion="${free_ram_gb}"
  else
    ram_gb_suggestion="${COLIBRI_DEFAULT_RAM_GB}"
  fi
  local RAM_GB
  RAM_GB="$(ask_input "RAM budget (GB)" "${ram_gb_suggestion}")"

  # --- Context length ---
  local CTX
  CTX="$(ask_input "Context window (tokens)" "${COLIBRI_DEFAULT_CTX}")"

  # --- API key ---
  local API_KEY
  API_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64)"

  # --- Resource limits ---
  local RAM_LIMIT CPU_LIMIT
  RAM_LIMIT="$(( RAM_GB + 2 ))g"
  CPU_LIMIT=12

  mkdir -p "${DEPLOY_DIR}"

  # --- Write .env ---
  write_env_file "colibri" "PORT=${PORT}
BIND_ADDR=${BIND_ADDR}
MODEL_DIR=${MODEL_DIR}
PROJECTS_DIR=${PROJECTS_DIR}
API_KEY=${API_KEY}
RAM_GB=${RAM_GB}
CTX=${CTX}
RAM_LIMIT=${RAM_LIMIT}
CPU_LIMIT=${CPU_LIMIT}
DIRECT=${DIRECT}
TS=${TS}"

  # --- Generate opencode config ---
  local SERVICE_URL
  SERVICE_URL="$(service_url "${PORT}")"

  mkdir -p "${DEPLOY_DIR}/config"
  cat > "${DEPLOY_DIR}/config/opencode.json" <<EOCONFIG
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "colibri": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Colibrí (local)",
      "options": {
        "baseURL": "${SERVICE_URL}/v1",
        "apiKey": "${API_KEY}"
      },
      "models": {
        "glm-5.2-colibri": {
          "name": "GLM-5.2 (744B MoE)",
          "limit": {
            "context": ${CTX},
            "output": 4096
          }
        }
      }
    }
  },
  "model": "colibri/glm-5.2-colibri",
  "enabled_providers": ["colibri"]
}
EOCONFIG

  # --- Build and start ---
  info "Building Colibrí image (this may take a few minutes)..."
  docker compose -f "${COLIBRI_DIR}/docker-compose.yml" \
    --env-file "${DEPLOY_DIR}/.env" build

  info "Starting Colibrí..."
  docker compose -f "${COLIBRI_DIR}/docker-compose.yml" \
    --env-file "${DEPLOY_DIR}/.env" up -d

  # --- Wait for health ---
  info "Waiting for Colibrí to become ready..."
  local retries=0 max_retries=30
  while (( retries < max_retries )); do
    if docker exec colibri python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" 2>/dev/null; then
      break
    fi
    sleep 2
    retries=$(( retries + 1 ))
  done

  if (( retries >= max_retries )); then
    warn "Colibrí may still be starting (model loading can take a while)."
    warn "Check logs: homekase logs colibri"
  fi

  # --- Save config ---
  config_app_set colibri installed true
  config_app_set colibri port      "${PORT}"
  config_app_set colibri tailscale "${TS}"
  config_app_set colibri model_dir "${MODEL_DIR}"
  config_app_set colibri projects_dir "${PROJECTS_DIR}"

  # --- Success ---
  local SERVICE_URL
  SERVICE_URL="$(service_url "${PORT}")"

  echo
  ok "Colibrí running on port ${PORT}  →  ${SERVICE_URL}"
  echo
  echo "  Model:    GLM-5.2 (744B MoE, int4)"
  echo "  Context:  ${CTX} tokens"
  echo "  RAM:      ${RAM_GB} GB allocated"
  echo "  Storage:  ${MODEL_DIR}"
  echo "  Projects: ${PROJECTS_DIR}"
  echo
  echo "  API Key:  ${API_KEY}"
  echo
  echo "  ─── Connect to OpenCode ───"
  echo
  echo "  Config generated at:"
  echo "    ${DEPLOY_DIR}/config/opencode.json"
  echo
  echo "  To use in any project, set:"
  echo "    export OPENCODE_CONFIG=${DEPLOY_DIR}/config/opencode.json"
  echo
  echo "  Or add to your fish config:"
  echo "    set -gx OPENCODE_CONFIG ${DEPLOY_DIR}/config/opencode.json"
  echo

  if [[ "${disk_type}" == "hdd" ]]; then
    warn "Disk: HDD detected — expect slower cold starts."
    warn "The learning cache warms up over time."
    echo
  fi
}

_update_colibri() {
  local COLIBRI_DIR="${HOMEKASE_REPO_DIR}/services/colibri"
  local DEPLOY_DIR="${HOMELAB_DIR}/colibri"

  local PORT TS BIND_ADDR MODEL_DIR PROJECTS_DIR API_KEY RAM_GB CTX RAM_LIMIT CPU_LIMIT DIRECT
  PORT="$(config_app_get colibri port 2>/dev/null || echo "4090")"
  TS="$(config_app_get colibri tailscale 2>/dev/null || echo "false")"
  BIND_ADDR="$(bind_address "${TS}")"
  MODEL_DIR="$(config_app_get colibri model_dir 2>/dev/null || echo "/storage/colibri/model")"
  PROJECTS_DIR="$(config_app_get colibri projects_dir 2>/dev/null || echo "/storage/colibri/projects")"

  if [[ -f "${DEPLOY_DIR}/.env" ]]; then
    # shellcheck source=/dev/null
    source "${DEPLOY_DIR}/.env"
  fi

  API_KEY="${API_KEY:-$(openssl rand -hex 32 2>/dev/null || echo 'changeme')}"
  RAM_GB="${RAM_GB:-${COLIBRI_DEFAULT_RAM_GB}}"
  CTX="${CTX:-${COLIBRI_DEFAULT_CTX}}"
  RAM_LIMIT="${RAM_LIMIT:-$(( RAM_GB + 2 ))g}"
  CPU_LIMIT="${CPU_LIMIT:-12}"
  DIRECT="${DIRECT:-0}"

  # --- Download model if missing ---
  if ! _download_colibri_model "${MODEL_DIR}"; then
    warn "Model missing — service may not start."
  fi

  mkdir -p "${DEPLOY_DIR}"

  write_env_file "colibri" "PORT=${PORT}
BIND_ADDR=${BIND_ADDR}
MODEL_DIR=${MODEL_DIR}
PROJECTS_DIR=${PROJECTS_DIR}
API_KEY=${API_KEY}
RAM_GB=${RAM_GB}
CTX=${CTX}
RAM_LIMIT=${RAM_LIMIT}
CPU_LIMIT=${CPU_LIMIT}
DIRECT=${DIRECT}
TS=${TS}"

  # Regenerate opencode config
  local SERVICE_URL
  SERVICE_URL="$(service_url "${PORT}")"

  mkdir -p "${DEPLOY_DIR}/config"
  cat > "${DEPLOY_DIR}/config/opencode.json" <<EOCONFIG
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "colibri": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Colibrí (local)",
      "options": {
        "baseURL": "${SERVICE_URL}/v1",
        "apiKey": "${API_KEY}"
      },
      "models": {
        "glm-5.2-colibri": {
          "name": "GLM-5.2 (744B MoE)",
          "limit": {
            "context": ${CTX},
            "output": 4096
          }
        }
      }
    }
  },
  "model": "colibri/glm-5.2-colibri",
  "enabled_providers": ["colibri"]
}
EOCONFIG

  info "Rebuilding Colibrí image..."
  docker compose -f "${COLIBRI_DIR}/docker-compose.yml" \
    --env-file "${DEPLOY_DIR}/.env" build \
    || warn "Image build failed, will reuse existing image on startup."
}

remove_colibri() {
  require_root
  header "Removing Colibrí LLM Engine"

  local port
  port="$(config_app_get colibri port 2>/dev/null || true)"
  if [[ -n "${port}" && "${port}" != "null" ]]; then
    tailscale_serve_remove "${port}"
  fi

  local COLIBRI_DIR="${HOMEKASE_REPO_DIR}/services/colibri"
  if [[ -f "${COLIBRI_DIR}/docker-compose.yml" ]]; then
    docker compose -f "${COLIBRI_DIR}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
  fi

  local DEPLOY_DIR="${HOMELAB_DIR}/colibri"
  local MODEL_DIR="" PROJECTS_DIR=""

  if [[ -f "${DEPLOY_DIR}/.env" ]]; then
    MODEL_DIR="$(grep '^MODEL_DIR=' "${DEPLOY_DIR}/.env" | cut -d= -f2 || true)"
    PROJECTS_DIR="$(grep '^PROJECTS_DIR=' "${DEPLOY_DIR}/.env" | cut -d= -f2 || true)"
  fi

  if [[ -n "${MODEL_DIR}" && -d "${MODEL_DIR}" ]]; then
    if ask_confirm "Delete model directory (${MODEL_DIR}, ~370GB)?"; then
      rm -rf "${MODEL_DIR}"
      ok "Removed ${MODEL_DIR}"
    else
      info "Model kept at ${MODEL_DIR}"
    fi
  fi

  if [[ -n "${PROJECTS_DIR}" && -d "${PROJECTS_DIR}" ]]; then
    if ask_confirm "Delete projects directory (${PROJECTS_DIR})?"; then
      rm -rf "${PROJECTS_DIR}"
      ok "Removed ${PROJECTS_DIR}"
    else
      info "Projects kept at ${PROJECTS_DIR}"
    fi
  fi

  # Clean up opencode config
  if [[ -d "${DEPLOY_DIR}/config" ]]; then
    rm -rf "${DEPLOY_DIR}/config"
  fi

  remove_service_dir "colibri"
  config_app_remove colibri
  ok "Colibri removed."
}
