#!/bin/bash

deploy_github_runner() {
  header "GitHub Actions Runner"

  local org
  org=$(prompt_input "  GitHub organization name" "")

  local runner_token
  runner_token=$(prompt_secret "  GitHub runner registration token")

  mkdir -p "$HOMELAB_DIR/github-runner"

  # Write secrets to .env file
  cat > "$HOMELAB_DIR/github-runner/.env" << ENV
REPO_URL=https://github.com/${org}
RUNNER_TOKEN=${runner_token}
ENV

  cat > "$HOMELAB_DIR/github-runner/docker-compose.yml" << 'RUNNER'
services:
  github-runner:
    image: myoung34/github-runner:2.319.1
    container_name: github-runner
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - RUNNER_LABELS=homelab
      - RUNNER_GROUP=Default
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
RUNNER

  docker compose -f "$HOMELAB_DIR/github-runner/docker-compose.yml" up -d

  ok "GitHub Actions runner registered for $org"
  info "Runner credentials saved to $HOMELAB_DIR/github-runner/.env"
}
