#!/bin/bash

declare -a SELECTED_SERVICES

service_menu() {
  header "Service Selection"
  echo "Select which services to install:"
  echo ""

  local services=(
    "jellyfin"     "Media server (movies, series, music)"
    "immich"       "Photo backup (Google Photos replacement)"
    "qbittorrent"  "Torrent client with VPN protection"
    "syncthing"    "File sync across devices"
    "beszel"       "Lightweight monitoring"
    "github-runner" "Self-hosted GitHub Actions runner"
  )

  local i=1
  local choices=()

  for ((idx=0; idx<${#services[@]}; idx+=2)); do
    local name="${services[idx]}"
    local desc="${services[idx+1]}"
    if prompt_yes_no "  ${i}) $desc?"; then
      choices+=("$name")
    fi
    ((i++))
  done

  SELECTED_SERVICES=("${choices[@]}")
}

deploy_selected_services() {
  for service in "${SELECTED_SERVICES[@]}"; do
    case "$service" in
      jellyfin)     deploy_jellyfin ;;
      immich)       deploy_immich ;;
      qbittorrent)  deploy_qbittorrent ;;
      syncthing)    deploy_syncthing ;;
      beszel)       deploy_beszel ;;
      github-runner) deploy_github_runner ;;
    esac
  done
}
