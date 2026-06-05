#!/bin/bash

# ASSISTANT_REPO comes from config.sh
ASSISTANT_DIR="$HOMELAB_DIR/assistant"

# Estimated RAM usage per service (MB)
# Used to calculate remaining RAM for AI assistant
estimate_services_ram() {
  local ram=0
  # Base system + Docker overhead
  ram=$((ram + 512))
  # Traefik + AdGuard (always deployed before assistant check)
  ram=$((ram + 256))

  for service in "${SELECTED_SERVICES[@]}"; do
    case "$service" in
      jellyfin)      ram=$((ram + 512)) ;;
      immich)        ram=$((ram + 1500)) ;;  # server + ml + db + redis
      qbittorrent)   ram=$((ram + 256)) ;;
      syncthing)     ram=$((ram + 128)) ;;
      beszel)        ram=$((ram + 64)) ;;
      github-runner) ram=$((ram + 256)) ;;
    esac
  done

  echo "$ram"
}

# Returns total system RAM in MB
get_total_ram_mb() {
  awk '/MemTotal/ {printf "%d", $2 / 1024}' /proc/meminfo
}

# Pick best model based on available RAM
# Returns: model_name ram_needed quality_label
recommend_model() {
  local available_mb="$1"

  # Model tiers (RAM = ollama + whisper + piper + agent overhead)
  # 14B: ~10GB model + 1.5GB whisper + 150MB piper/agent = ~12GB
  # 7B:  ~5GB model  + 1.5GB whisper + 150MB piper/agent = ~7GB
  # 3B:  ~2.5GB model + 1GB whisper-tiny + 150MB         = ~4GB

  if [ "$available_mb" -ge "${ASSISTANT_RAM_EXCELLENT:-12288}" ]; then
    echo "qwen2.5:14b ${ASSISTANT_RAM_EXCELLENT:-12288} excellent"
  elif [ "$available_mb" -ge "${ASSISTANT_RAM_GOOD:-7168}" ]; then
    echo "qwen2.5:7b ${ASSISTANT_RAM_GOOD:-7168} good"
  elif [ "$available_mb" -ge "${ASSISTANT_RAM_BASIC:-4096}" ]; then
    echo "qwen2.5:3b ${ASSISTANT_RAM_BASIC:-4096} basic"
  else
    echo "none 0 insufficient"
  fi
}

deploy_assistant() {
  section "AI Assistant" \
    "Local AI assistant with voice interaction, dashboard widgets, and tool integration. Uses Ollama for inference, Whisper for speech-to-text, and Piper for text-to-speech."

  if docker compose ls 2>/dev/null | grep -q assistant; then
    info "Assistant already running, skipping"
    return
  fi

  # Calculate available RAM
  local total_ram
  total_ram=$(get_total_ram_mb)
  local services_ram
  services_ram=$(estimate_services_ram)
  local available_ram=$((total_ram - services_ram))

  info "System RAM: $((total_ram / 1024))GB total, ~$((services_ram / 1024))GB used by services"
  info "Available for AI: ~$((available_ram / 1024))GB"

  # Build model options based on available RAM
  local model_options=()
  local model_names=()
  if [ "$available_ram" -ge "${ASSISTANT_RAM_EXCELLENT:-12288}" ]; then
    model_options+=("qwen2.5:14b — ~12GB RAM — excellent quality, reliable tool calling, good summarization")
    model_names+=("qwen2.5:14b")
  fi
  if [ "$available_ram" -ge "${ASSISTANT_RAM_GOOD:-7168}" ]; then
    model_options+=("qwen2.5:7b — ~7GB RAM — good quality, solid tool calling, decent summarization")
    model_names+=("qwen2.5:7b")
  fi
  if [ "$available_ram" -ge "${ASSISTANT_RAM_BASIC:-4096}" ]; then
    model_options+=("qwen2.5:3b — ~4GB RAM — basic quality, simple tasks OK, may struggle with complex tasks")
    model_names+=("qwen2.5:3b")
  fi
  model_options+=("skip — Don't deploy AI Assistant")
  model_names+=("skip")

  if [ ${#model_options[@]} -eq 1 ]; then
    warn "Not enough RAM for AI Assistant (need at least 4GB free, have $((available_ram / 1024))GB)"
    info "AI Assistant skipped"
    return
  fi

  echo ""
  local model_choice
  model_choice=$(prompt_choose "Which AI model do you want?" "${model_options[@]}")

  # Map choice back to model name
  local model_name=""
  for i in "${!model_options[@]}"; do
    if [[ "${model_options[$i]}" == "$model_choice" ]]; then
      model_name="${model_names[$i]}"
      break
    fi
  done

  if [ "$model_name" = "skip" ] || [ -z "$model_name" ]; then
    info "AI Assistant skipped"
    return
  fi

  echo ""
  case "$quality" in
    excellent)
      ok "Recommended: $model_name (~$((model_ram / 1024))GB) — excellent quality"
      info "Best model for your hardware. Reliable tool calling, good summarization."
      ;;
    good)
      ok "Recommended: $model_name (~$((model_ram / 1024))GB) — good quality"
      info "Solid model. Good tool calling, decent summarization."
      ;;
    basic)
      warn "Recommended: $model_name (~$((model_ram / 1024))GB) — basic quality"
      info "Smaller model due to RAM constraints. Simple tasks OK, complex tasks may struggle."
      ;;
  esac
  echo ""

  if ! prompt_yes_no "Deploy AI Assistant with $model_name?"; then
    info "AI Assistant skipped"
    return
  fi

  # Clone or update assistant repo
  if dir_exists "$ASSISTANT_DIR"; then
    info "Updating assistant..."
    git -C "$ASSISTANT_DIR" pull --quiet
  else
    info "Cloning assistant..."
    if is_installed gh && gh auth status 2>/dev/null; then
      gh repo clone FabriSilve/homekase-assistant "$ASSISTANT_DIR"
    else
      local gh_token
      gh_token=$(prompt_secret "GitHub personal access token (classic, with repo scope)")
      git clone --depth=1 "https://FabriSilve:${gh_token}@github.com/FabriSilve/homekase-assistant.git" "$ASSISTANT_DIR"
    fi
  fi

  # Write model config
  mkdir -p /data/config/assistant
  cat > /data/config/assistant/.env << ENV
OLLAMA_MODEL=${model_name}
ENV

  # Build and start
  info "Building assistant containers (this may take a few minutes)..."
  docker compose -f "$ASSISTANT_DIR/docker-compose.yml" build --quiet
  docker compose -f "$ASSISTANT_DIR/docker-compose.yml" up -d

  # Pull the recommended model
  info "Pulling $model_name model (this may take a while on first run)..."
  docker exec ollama ollama pull "$model_name" || warn "Model pull failed — run manually: docker exec ollama ollama pull $model_name"

  append_url "Assistant     → http://assistant.home"

  ok "AI Assistant deployed at http://assistant.home"
  info "Model: $model_name ($quality quality)"
  info "Config: /data/config/assistant/.env"
}
