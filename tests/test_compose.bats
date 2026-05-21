#!/usr/bin/env bats

# Test that deploy functions generate valid compose YAML
# Uses mocked docker/system commands and temp directories

setup() {
  load 'test_helper'
  export TMPDIR_TEST=$(mktemp -d)

  # Override paths to temp dir
  export HOMELAB_DIR="$TMPDIR_TEST/homelab"
  export DATA_DIR="$TMPDIR_TEST/data"
  export STORAGE_DIR="$TMPDIR_TEST/storage"
  mkdir -p "$HOMELAB_DIR/traefik" "$DATA_DIR" "$STORAGE_DIR"

  # Source common — must come AFTER exporting vars so they override defaults
  source "${BATS_TEST_DIRNAME}/../lib/common.sh"

  # Re-override paths (common.sh sets them)
  HOMELAB_DIR="$TMPDIR_TEST/homelab"
  DATA_DIR="$TMPDIR_TEST/data"
  STORAGE_DIR="$TMPDIR_TEST/storage"

  # Mock docker so compose ls returns nothing (service not running)
  docker() { return 1; }
  export -f docker
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "compose: traefik generates valid docker-compose.yml" {
  openssl() {
    case "$1" in
      rand) echo "testpass123";;
      passwd) echo 'testhash';;
    esac
  }
  prompt_yes_no() { return 1; }
  export -f openssl prompt_yes_no

  source "${BATS_TEST_DIRNAME}/../lib/traefik.sh"
  run deploy_traefik
  assert_success

  [ -f "$HOMELAB_DIR/traefik/docker-compose.yml" ]
  run grep "image: traefik" "$HOMELAB_DIR/traefik/docker-compose.yml"
  assert_success
  run grep "traefik-net" "$HOMELAB_DIR/traefik/docker-compose.yml"
  assert_success
}

@test "compose: jellyfin generates valid docker-compose.yml" {
  source "${BATS_TEST_DIRNAME}/../lib/jellyfin.sh"
  run deploy_jellyfin
  assert_success

  [ -f "$HOMELAB_DIR/jellyfin/docker-compose.yml" ]
  run grep "jellyfin" "$HOMELAB_DIR/jellyfin/docker-compose.yml"
  assert_success
}

@test "compose: syncthing generates valid docker-compose.yml" {
  source "${BATS_TEST_DIRNAME}/../lib/syncthing.sh"
  run deploy_syncthing
  assert_success

  [ -f "$HOMELAB_DIR/syncthing/docker-compose.yml" ]
  run grep "syncthing" "$HOMELAB_DIR/syncthing/docker-compose.yml"
  assert_success
}

@test "compose: beszel generates valid docker-compose.yml" {
  source "${BATS_TEST_DIRNAME}/../lib/beszel.sh"
  run deploy_beszel
  assert_success

  [ -f "$HOMELAB_DIR/monitoring/docker-compose.yml" ]
  run grep "beszel" "$HOMELAB_DIR/monitoring/docker-compose.yml"
  assert_success
}

@test "compose: immich generates compose with .env file" {
  prompt_secret() { echo "testdbpass"; }
  openssl() { echo "testgenerated"; }
  export -f prompt_secret openssl

  source "${BATS_TEST_DIRNAME}/../lib/immich.sh"
  run deploy_immich
  assert_success

  [ -f "$HOMELAB_DIR/immich/docker-compose.yml" ]
  [ -f "$HOMELAB_DIR/immich/.env" ]
  run grep "DB_PASSWORD" "$HOMELAB_DIR/immich/.env"
  assert_success
}

@test "compose: github-runner uses env_file" {
  prompt_input() { echo "testorg"; }
  prompt_secret() { echo "testtoken"; }
  export -f prompt_input prompt_secret

  source "${BATS_TEST_DIRNAME}/../lib/github-runner.sh"
  run deploy_github_runner
  assert_success

  [ -f "$HOMELAB_DIR/github-runner/docker-compose.yml" ]
  [ -f "$HOMELAB_DIR/github-runner/.env" ]
  run grep "env_file" "$HOMELAB_DIR/github-runner/docker-compose.yml"
  assert_success
}

@test "compose: adguard pre-seeds admin config" {
  prompt_yes_no() { return 0; }
  openssl() {
    case "$1" in
      rand) echo "testpass";;
      passwd) echo 'testhash';;
    esac
  }
  hostname() { echo "192.168.1.1"; }
  export -f prompt_yes_no openssl hostname

  source "${BATS_TEST_DIRNAME}/../lib/adguard.sh"
  run deploy_adguard
  assert_success

  [ -f "$HOMELAB_DIR/traefik/adguard.yml" ]
  [ -f "$DATA_DIR/config/adguard/conf/AdGuardHome.yaml" ]
  run grep "admin" "$DATA_DIR/config/adguard/conf/AdGuardHome.yaml"
  assert_success
}
