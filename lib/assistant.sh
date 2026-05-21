#!/bin/bash

ASSISTANT_REPO="https://github.com/FabriSilve/homekase-assistant.git"
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

  if [ "$available_mb" -ge 12288 ]; then
    echo "qwen2.5:14b 12288 excellent"
  elif [ "$available_mb" -ge 7168 ]; then
    echo "qwen2.5:7b 7168 good"
  elif [ "$available_mb" -ge 4096 ]; then
    echo "qwen2.5:3b 4096 basic"
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

  # Get model recommendation
  local recommendation
  recommendation=$(recommend_model "$available_ram")
  local model_name model_ram quality
  model_name=$(echo "$recommendation" | cut -d' ' -f1)
  model_ram=$(echo "$recommendation" | cut -d' ' -f2)
  quality=$(echo "$recommendation" | cut -d' ' -f3)

  info "System RAM: $((total_ram / 1024))GB total, ~$((services_ram / 1024))GB used by services"
  info "Available for AI: ~$((available_ram / 1024))GB"

  if [ "$model_name" = "none" ]; then
    warn "Not enough RAM for AI Assistant (need at least 4GB free, have $((available_ram / 1024))GB)"
    warn "Consider disabling some services or upgrading RAM"
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
    git clone --depth=1 "$ASSISTANT_REPO" "$ASSISTANT_DIR"
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
