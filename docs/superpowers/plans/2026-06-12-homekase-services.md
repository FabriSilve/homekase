# homekase Services (list/add/remove) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three stub functions in `lib/services/service.sh` with a working dispatcher plus six service installers (jellyfin, immich, qbittorrent, filebrowser, vikunja, assistant), each driven by an interactive wizard and backed by Docker Compose.

**Architecture:** `lib/services/service.sh` owns the command dispatcher and service registry array. `lib/services/_common.sh` owns port allocation, docker-compose write helpers, Tailscale Serve integration, and teardown. Each service (e.g. `lib/services/jellyfin.sh`) owns its own `deploy_<name>` and `remove_<name>` functions and is sourced on demand. Config state is persisted to `homekase.yml` via existing `config_app_set` / `config_app_get` functions. Tests run with bats using a temp config file — no Docker daemon needed.

**Tech Stack:** bash 5+, yq v4 (YAML), Docker Compose v2, gum (optional interactive prompts), bats-core (tests), ss (socket stats for port collision check), openssl (DB password generation), tailscale CLI

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/services/service.sh` | REPLACE stub | Dispatcher: `cmd_list`, `cmd_add <name>`, `cmd_remove <name>`; service registry array |
| `lib/services/_common.sh` | CREATE | `next_available_port`, `port_wizard`, `tailscale_serve_setup`, `write_service_dir`, `write_env_file`, `write_compose_file`, `start_service`, `stop_service`, `remove_service_dir` |
| `lib/services/jellyfin.sh` | CREATE | `deploy_jellyfin`, `remove_jellyfin` |
| `lib/services/immich.sh` | CREATE | `deploy_immich`, `remove_immich` |
| `lib/services/qbittorrent.sh` | CREATE | `deploy_qbittorrent`, `remove_qbittorrent` |
| `lib/services/filebrowser.sh` | CREATE | `deploy_filebrowser`, `remove_filebrowser` |
| `lib/services/vikunja.sh` | CREATE | `deploy_vikunja`, `remove_vikunja` |
| `lib/services/assistant.sh` | CREATE | `deploy_assistant`, `remove_assistant` |
| `tests/test_services.bats` | CREATE | unit tests for dispatcher + common helpers (no Docker needed) |

---

## Task 1: `lib/services/_common.sh` — shared helpers

**Files:**
- Create: `lib/services/_common.sh`
- Create: `tests/test_services.bats` (failing stubs for tests defined here)

- [ ] **Step 1: Write the failing tests for `next_available_port`**

Create `tests/test_services.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/services/_common.sh"
  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test.XXXXX)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG
}

teardown() {
  rm -f "$HOMEKASE_CONFIG"
}

@test "next_available_port returns a number when no apps configured" {
  result="$(next_available_port)"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "next_available_port returns a number when apps have ports" {
  config_app_set "jellyfin" "port" "4000"
  config_app_set "immich"   "port" "4010"
  result="$(next_available_port)"
  [[ "$result" =~ ^[0-9]+$ ]]
}

@test "next_available_port suggests higher port than existing ones" {
  config_app_set "jellyfin" "port" "4000"
  result="$(next_available_port)"
  [ "$result" -gt 4000 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/fabrizio/Projects/homekase && bats tests/test_services.bats
```

Expected: FAIL — `_common.sh: No such file or directory`

- [ ] **Step 3: Create `lib/services/_common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for all service installers.
# Sourced by lib/services/service.sh after common.sh and config.sh are loaded.

HOMELAB_DIR="${HOMELAB_DIR:-/opt/homelab}"
DEFAULT_FIRST_PORT=4000
PORT_STEP=10

# Returns the next suggested free port by reading all app ports from config,
# taking the maximum, and adding PORT_STEP. Falls back to DEFAULT_FIRST_PORT.
next_available_port() {
  local max_port=$((DEFAULT_FIRST_PORT - PORT_STEP))
  local port_list
  # yq returns "null" when the key path doesn't exist
  port_list="$(yq '.apps.*.port // ""' "$HOMEKASE_CONFIG" 2>/dev/null)" || true
  while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    (( p > max_port )) && max_port=$p
  done <<< "$port_list"
  echo $(( max_port + PORT_STEP ))
}

# Interactively asks user to pick a start port for a service.
# Usage: port_wizard <service_name> <num_ports>
# Prints the chosen port number to stdout.
port_wizard() {
  local service_name="$1"
  local num_ports="${2:-1}"
  local suggestion
  suggestion="$(next_available_port)"
  local chosen
  chosen="$(ask_input "Port for ${service_name} (needs ${num_ports} port(s))" "$suggestion")"
  # Validate it is a number
  if ! [[ "$chosen" =~ ^[0-9]+$ ]]; then
    error "Invalid port: $chosen"
    exit 1
  fi
  # Warn if port appears already in use (non-fatal — user may know better)
  if ss -tlnp 2>/dev/null | grep -q ":${chosen} "; then
    warn "Port ${chosen} appears to be in use. Proceeding anyway."
  fi
  echo "$chosen"
}

# Sets up Tailscale Serve for a given port if Tailscale is installed.
# Usage: tailscale_serve_setup <port>
# Prints "true" or "false" to stdout (for storing in .env / labels).
tailscale_serve_setup() {
  local port="$1"
  local ts_installed
  ts_installed="$(config_get 'tailscale.installed' 2>/dev/null || echo 'false')"
  if [[ "$ts_installed" != "true" ]]; then
    echo "false"
    return 0
  fi
  if ask_confirm "Expose port ${port} via Tailscale Serve (HTTPS)?"; then
    tailscale serve https "$port" http://localhost:"$port" \
      || warn "tailscale serve failed — check tailscale status"
    echo "true"
  else
    echo "false"
  fi
}

# Creates /opt/homelab/<name>/ directory.
write_service_dir() {
  local name="$1"
  mkdir -p "${HOMELAB_DIR}/${name}"
}

# Writes /opt/homelab/<name>/.env from the given content string.
# Usage: write_env_file <name> <content>
write_env_file() {
  local name="$1"
  local content="$2"
  printf '%s\n' "$content" > "${HOMELAB_DIR}/${name}/.env"
}

# Writes /opt/homelab/<name>/docker-compose.yml from the given content string.
# Usage: write_compose_file <name> <content>
write_compose_file() {
  local name="$1"
  local content="$2"
  printf '%s\n' "$content" > "${HOMELAB_DIR}/${name}/docker-compose.yml"
}

# Starts a service via Docker Compose.
start_service() {
  local name="$1"
  docker compose -f "${HOMELAB_DIR}/${name}/docker-compose.yml" up -d
}

# Stops a service via Docker Compose.
stop_service() {
  local name="$1"
  docker compose -f "${HOMELAB_DIR}/${name}/docker-compose.yml" down 2>/dev/null || true
}

# Stops a service and optionally removes its directory.
# Usage: remove_service_dir <name>
remove_service_dir() {
  local name="$1"
  stop_service "$name"
  if ask_confirm "Also delete data in ${HOMELAB_DIR}/${name}?"; then
    rm -rf "${HOMELAB_DIR:?}/${name}"
    ok "Removed ${HOMELAB_DIR}/${name}"
  else
    info "Data kept at ${HOMELAB_DIR}/${name}"
  fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/fabrizio/Projects/homekase && bats tests/test_services.bats
```

Expected output:
```
 ✓ next_available_port returns a number when no apps configured
 ✓ next_available_port returns a number when apps have ports
 ✓ next_available_port suggests higher port than existing ones

3 tests, 0 failures
```

- [ ] **Step 5: Run shellcheck on the new file**

```bash
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/_common.sh
```

Expected: no output (exit 0)

- [ ] **Step 6: Commit**

```bash
git add lib/services/_common.sh tests/test_services.bats
git commit -m "feat: add services _common.sh with port wizard and compose helpers"
```

---

## Task 2: `lib/services/service.sh` — dispatcher + `cmd_list`

**Files:**
- Modify: `lib/services/service.sh` (replace stub)
- Modify: `tests/test_services.bats` (add dispatcher tests)

- [ ] **Step 1: Add failing tests for the dispatcher and cmd_list**

Append to `tests/test_services.bats` (inside the same file, after the existing tests):

```bash
# ── Dispatcher tests (source service.sh, not _common.sh directly) ──────────

@test "cmd_list exits 0" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_success
}

@test "cmd_list output contains jellyfin" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "jellyfin"
}

@test "cmd_list output contains immich" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "immich"
}

@test "cmd_list output contains qbittorrent" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "qbittorrent"
}

@test "cmd_list output contains filebrowser" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "filebrowser"
}

@test "cmd_list output contains vikunja" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "vikunja"
}

@test "cmd_list output contains assistant" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_list
  assert_output --partial "assistant"
}

@test "cmd_add with unknown name exits 1" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_add "__no_such_service__"
  assert_failure
}

@test "cmd_add with unknown name output contains error" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_add "__no_such_service__"
  assert_output --partial "Unknown service"
}

@test "cmd_remove with unknown name exits 1" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_remove "__no_such_service__"
  assert_failure
}

@test "cmd_remove with unknown name output contains error" {
  source "$PROJECT_ROOT/lib/services/service.sh"
  run cmd_remove "__no_such_service__"
  assert_output --partial "Unknown service"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/fabrizio/Projects/homekase && bats tests/test_services.bats
```

Expected: previously passing tests still pass; new dispatcher tests FAIL with "not yet implemented"

- [ ] **Step 3: Replace `lib/services/service.sh` with the real implementation**

```bash
#!/usr/bin/env bash
# Service dispatcher — list, add, remove.
# Sourced by the homekase main entry point after common.sh and config.sh.

HOMEKASE_DIR="${HOMEKASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck source=lib/services/_common.sh
source "$HOMEKASE_DIR/lib/services/_common.sh"

# Registry: "name:description"  (one entry per line, no spaces around colon)
SERVICES=(
  "jellyfin:Media server (movies, TV, music)"
  "immich:Photo backup with AI tagging"
  "qbittorrent:Torrent client with optional VPN"
  "filebrowser:Web file manager for family sharing"
  "vikunja:Task management and calendar"
  "assistant:Local AI assistant (RAM-gated)"
)

# Returns the description for a service name, or empty string if not found.
_service_description() {
  local name="$1"
  local entry
  for entry in "${SERVICES[@]}"; do
    local sname="${entry%%:*}"
    local sdesc="${entry#*:}"
    if [[ "$sname" == "$name" ]]; then
      echo "$sdesc"
      return 0
    fi
  done
  echo ""
}

# Returns 0 if name is in SERVICES registry.
_service_known() {
  local name="$1"
  local entry
  for entry in "${SERVICES[@]}"; do
    [[ "${entry%%:*}" == "$name" ]] && return 0
  done
  return 1
}

# homekase list
cmd_list() {
  header "Available services"
  printf "%-18s %-42s %-12s %-8s %s\n" "NAME" "DESCRIPTION" "STATUS" "PORT" "URL"
  printf '%0.s─' {1..90}; echo

  local entry sname sdesc status port url ts_host
  ts_host="$(config_get 'tailscale.hostname' 2>/dev/null || echo '')"

  for entry in "${SERVICES[@]}"; do
    sname="${entry%%:*}"
    sdesc="${entry#*:}"

    if config_app_installed "$sname" 2>/dev/null; then
      status="${GREEN}installed${RESET}"
      port="$(config_app_get "$sname" "port" 2>/dev/null || echo '-')"
      local ts_flag
      ts_flag="$(config_app_get "$sname" "tailscale" 2>/dev/null || echo 'false')"
      if [[ "$ts_flag" == "true" && -n "$ts_host" ]]; then
        url="https://${ts_host}:${port}"
      elif [[ -n "$port" && "$port" != "null" && "$port" != "-" ]]; then
        url="http://localhost:${port}"
      else
        url="-"
      fi
    else
      status="not installed"
      port="-"
      url="-"
    fi

    printf "%-18s %-42s %-20s %-8s %s\n" \
      "$sname" "$sdesc" "$status" "$port" "$url"
  done
  echo
}

# homekase add <name>
cmd_add() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    error "Usage: homekase add <name>"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  if ! _service_known "$name"; then
    error "Unknown service: $name"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$HOMEKASE_DIR/lib/services/${name}.sh"
  "deploy_${name}"
}

# homekase remove <name>
cmd_remove() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    error "Usage: homekase remove <name>"
    exit 1
  fi
  if ! _service_known "$name"; then
    error "Unknown service: $name"
    echo "Run 'homekase list' to see available services."
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$HOMEKASE_DIR/lib/services/${name}.sh"
  "remove_${name}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/fabrizio/Projects/homekase && bats tests/test_services.bats
```

Expected output (all 14 tests pass):
```
 ✓ next_available_port returns a number when no apps configured
 ✓ next_available_port returns a number when apps have ports
 ✓ next_available_port suggests higher port than existing ones
 ✓ cmd_list exits 0
 ✓ cmd_list output contains jellyfin
 ✓ cmd_list output contains immich
 ✓ cmd_list output contains qbittorrent
 ✓ cmd_list output contains filebrowser
 ✓ cmd_list output contains vikunja
 ✓ cmd_list output contains assistant
 ✓ cmd_add with unknown name exits 1
 ✓ cmd_add with unknown name output contains error
 ✓ cmd_remove with unknown name exits 1
 ✓ cmd_remove with unknown name output contains error

14 tests, 0 failures
```

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
cd /Users/fabrizio/Projects/homekase && make check
```

Expected: all existing tests still pass, shellcheck clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/service.sh tests/test_services.bats
git commit -m "feat: implement cmd_list, cmd_add, cmd_remove dispatcher in service.sh"
```

---

## Task 3: `lib/services/jellyfin.sh`

**Files:**
- Create: `lib/services/jellyfin.sh`

- [ ] **Step 1: Create `lib/services/jellyfin.sh`**

```bash
#!/usr/bin/env bash
# Jellyfin service installer.
# Sourced by lib/services/service.sh on `homekase add jellyfin`.

deploy_jellyfin() {
  require_root
  header "Installing Jellyfin"

  local PORT DATA_PATH MEDIA_PATH TS

  PORT="$(port_wizard "jellyfin" 1)"
  DATA_PATH="$(ask_input "Jellyfin config/data path" "/data/config/jellyfin")"
  MEDIA_PATH="$(ask_input "Media storage path" "/storage/media")"
  TS="$(tailscale_serve_setup "$PORT")"

  write_service_dir "jellyfin"

  write_compose_file "jellyfin" "services:
  jellyfin:
    image: jellyfin/jellyfin:10.9.11
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - \"\${PORT}:8096\"
    volumes:
      - \${DATA_PATH}:/config
      - \${MEDIA_PATH}:/media:ro
    networks:
      - homelab-net
    labels:
      com.homekase.service: jellyfin
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: none
networks:
  homelab-net:
    external: true"

  write_env_file "jellyfin" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
MEDIA_PATH=${MEDIA_PATH}
TS=${TS}"

  mkdir -p "$DATA_PATH" "$MEDIA_PATH"

  start_service "jellyfin"

  config_app_set jellyfin installed true
  config_app_set jellyfin port      "$PORT"
  config_app_set jellyfin data_path "$DATA_PATH"
  config_app_set jellyfin storage_path "$MEDIA_PATH"
  config_app_set jellyfin tailscale "$TS"

  ok "Jellyfin running on port ${PORT}  →  http://localhost:${PORT}"
}

remove_jellyfin() {
  require_root
  header "Removing Jellyfin"
  remove_service_dir "jellyfin"
  config_app_set jellyfin installed false
  ok "Jellyfin removed."
}
```

- [ ] **Step 2: Verify bash syntax and shellcheck**

```bash
bash -n /Users/fabrizio/Projects/homekase/lib/services/jellyfin.sh && echo "syntax OK"
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/jellyfin.sh
```

Expected: `syntax OK`, no shellcheck output.

- [ ] **Step 3: Commit**

```bash
git add lib/services/jellyfin.sh
git commit -m "feat: add jellyfin service installer"
```

---

## Task 4: `lib/services/immich.sh`

**Files:**
- Create: `lib/services/immich.sh`

- [ ] **Step 1: Create `lib/services/immich.sh`**

```bash
#!/usr/bin/env bash
# Immich service installer.
# Sourced by lib/services/service.sh on `homekase add immich`.
# Deploys: immich-server, immich-machine-learning, postgres (pgvecto-rs), redis.

deploy_immich() {
  require_root
  header "Installing Immich"

  local PORT DATA_PATH PHOTOS_PATH DB_PASS TS

  PORT="$(port_wizard "immich" 1)"
  DATA_PATH="$(ask_input "Postgres data path" "/data/config/immich")"
  PHOTOS_PATH="$(ask_input "Photos upload path" "/storage/photos")"
  DB_PASS="$(openssl rand -base64 16)"
  TS="$(tailscale_serve_setup "$PORT")"

  write_service_dir "immich"

  write_compose_file "immich" "services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-server
    restart: unless-stopped
    command: [\"start.sh\", \"immich\"]
    depends_on:
      - redis
      - database
    ports:
      - \"\${PORT}:3001\"
    volumes:
      - \${PHOTOS_PATH}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    networks:
      - homelab-net
    labels:
      com.homekase.service: immich
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${PHOTOS_PATH}\"
      com.homekase.backup.db-type: postgres

  immich-microservices:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-microservices
    restart: unless-stopped
    command: [\"start.sh\", \"microservices\"]
    depends_on:
      - redis
      - database
    volumes:
      - \${PHOTOS_PATH}:/usr/src/app/upload
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    networks:
      - homelab-net

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:release
    container_name: immich-machine-learning
    restart: unless-stopped
    volumes:
      - immich-model-cache:/cache
    env_file: .env
    networks:
      - homelab-net

  redis:
    image: redis:6.2-alpine
    container_name: immich-redis
    restart: unless-stopped
    networks:
      - homelab-net

  database:
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    container_name: immich-postgres
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: \${DB_PASS}
      POSTGRES_USER: immich
      POSTGRES_DB: immich
    volumes:
      - \${DATA_PATH}:/var/lib/postgresql/data
    networks:
      - homelab-net

volumes:
  immich-model-cache:

networks:
  homelab-net:
    external: true"

  write_env_file "immich" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
PHOTOS_PATH=${PHOTOS_PATH}
DB_PASS=${DB_PASS}
TS=${TS}
DB_HOSTNAME=database
DB_USERNAME=immich
DB_DATABASE_NAME=immich
REDIS_HOSTNAME=redis
IMMICH_SERVER_URL=http://immich-server:3001"

  mkdir -p "$DATA_PATH" "$PHOTOS_PATH"

  start_service "immich"

  config_app_set immich installed   true
  config_app_set immich port        "$PORT"
  config_app_set immich data_path   "$DATA_PATH"
  config_app_set immich storage_path "$PHOTOS_PATH"
  config_app_set immich tailscale   "$TS"

  ok "Immich running on port ${PORT}  →  http://localhost:${PORT}"
}

remove_immich() {
  require_root
  header "Removing Immich"
  remove_service_dir "immich"
  config_app_set immich installed false
  ok "Immich removed."
}
```

- [ ] **Step 2: Verify bash syntax and shellcheck**

```bash
bash -n /Users/fabrizio/Projects/homekase/lib/services/immich.sh && echo "syntax OK"
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/immich.sh
```

Expected: `syntax OK`, no shellcheck output.

- [ ] **Step 3: Commit**

```bash
git add lib/services/immich.sh
git commit -m "feat: add immich service installer"
```

---

## Task 5: `lib/services/qbittorrent.sh`

**Files:**
- Create: `lib/services/qbittorrent.sh`

- [ ] **Step 1: Create `lib/services/qbittorrent.sh`**

```bash
#!/usr/bin/env bash
# qBittorrent service installer (with optional Gluetun VPN).
# Sourced by lib/services/service.sh on `homekase add qbittorrent`.

deploy_qbittorrent() {
  require_root
  header "Installing qBittorrent"

  local PORT TORRENTS_PATH USE_VPN TS
  local WG_PRIVATE_KEY WG_SERVER WG_SERVER_PUBKEY

  PORT="$(port_wizard "qbittorrent" 1)"
  TORRENTS_PATH="$(ask_input "Torrents storage path" "/storage/torrents")"
  TS="$(tailscale_serve_setup "$PORT")"

  if ask_confirm "Route traffic through VPN (Gluetun/WireGuard)?"; then
    USE_VPN="true"
    WG_PRIVATE_KEY="$(ask_input "WireGuard private key" "")"
    WG_SERVER="$(ask_input "WireGuard server address (e.g. vpn.example.com)" "")"
    WG_SERVER_PUBKEY="$(ask_input "WireGuard server public key" "")"
  else
    USE_VPN="false"
    WG_PRIVATE_KEY=""
    WG_SERVER=""
    WG_SERVER_PUBKEY=""
  fi

  write_service_dir "qbittorrent"

  if [[ "$USE_VPN" == "true" ]]; then
    write_compose_file "qbittorrent" "services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - \"\${PORT}:8080\"
    environment:
      VPN_SERVICE_PROVIDER: custom
      VPN_TYPE: wireguard
      WIREGUARD_PRIVATE_KEY: \${WG_PRIVATE_KEY}
      WIREGUARD_ADDRESSES: 10.64.0.1/32
      VPN_ENDPOINT_IP: \${WG_SERVER}
      WIREGUARD_PUBLIC_KEY: \${WG_SERVER_PUBKEY}
    networks:
      - homelab-net

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    network_mode: service:gluetun
    depends_on:
      - gluetun
    environment:
      PUID: 1000
      PGID: 1000
      WEBUI_PORT: 8080
    volumes:
      - \${TORRENTS_PATH}:/downloads
    labels:
      com.homekase.service: qbittorrent
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: none
      com.homekase.backup.db-type: none

networks:
  homelab-net:
    external: true"
  else
    write_compose_file "qbittorrent" "services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
      WEBUI_PORT: 8080
    ports:
      - \"\${PORT}:8080\"
    volumes:
      - \${TORRENTS_PATH}:/downloads
    networks:
      - homelab-net
    labels:
      com.homekase.service: qbittorrent
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: none
      com.homekase.backup.db-type: none

networks:
  homelab-net:
    external: true"
  fi

  write_env_file "qbittorrent" "PORT=${PORT}
TORRENTS_PATH=${TORRENTS_PATH}
TS=${TS}
USE_VPN=${USE_VPN}
WG_PRIVATE_KEY=${WG_PRIVATE_KEY}
WG_SERVER=${WG_SERVER}
WG_SERVER_PUBKEY=${WG_SERVER_PUBKEY}"

  mkdir -p "$TORRENTS_PATH"

  start_service "qbittorrent"

  config_app_set qbittorrent installed    true
  config_app_set qbittorrent port         "$PORT"
  config_app_set qbittorrent storage_path "$TORRENTS_PATH"
  config_app_set qbittorrent tailscale    "$TS"

  ok "qBittorrent running on port ${PORT}  →  http://localhost:${PORT}"
}

remove_qbittorrent() {
  require_root
  header "Removing qBittorrent"
  remove_service_dir "qbittorrent"
  config_app_set qbittorrent installed false
  ok "qBittorrent removed."
}
```

- [ ] **Step 2: Verify bash syntax and shellcheck**

```bash
bash -n /Users/fabrizio/Projects/homekase/lib/services/qbittorrent.sh && echo "syntax OK"
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/qbittorrent.sh
```

Expected: `syntax OK`, no shellcheck output.

- [ ] **Step 3: Commit**

```bash
git add lib/services/qbittorrent.sh
git commit -m "feat: add qbittorrent service installer with optional VPN"
```

---

## Task 6: `lib/services/filebrowser.sh`

**Files:**
- Create: `lib/services/filebrowser.sh`

- [ ] **Step 1: Create `lib/services/filebrowser.sh`**

```bash
#!/usr/bin/env bash
# Filebrowser service installer.
# Sourced by lib/services/service.sh on `homekase add filebrowser`.
# Admin password is set via the filebrowser --password flag at first startup.

deploy_filebrowser() {
  require_root
  header "Installing Filebrowser"

  local PORT STORAGE_PATH ADMIN_PASSWORD TS

  PORT="$(port_wizard "filebrowser" 1)"
  STORAGE_PATH="$(ask_input "Storage root to browse" "/storage")"
  ADMIN_PASSWORD="$(ask_input "Admin password (shown once, stored in .env)" "")"
  TS="$(tailscale_serve_setup "$PORT")"

  write_service_dir "filebrowser"

  write_compose_file "filebrowser" "services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    ports:
      - \"\${PORT}:80\"
    volumes:
      - \${STORAGE_PATH}:/srv
      - /opt/homelab/filebrowser/filebrowser.db:/database.db
    environment:
      FB_PASSWORD: \${ADMIN_PASSWORD}
    command: --database /database.db --root /srv --port 80 --address 0.0.0.0
    networks:
      - homelab-net
    labels:
      com.homekase.service: filebrowser
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: /opt/homelab/filebrowser/filebrowser.db
      com.homekase.backup.db-type: sqlite

networks:
  homelab-net:
    external: true"

  write_env_file "filebrowser" "PORT=${PORT}
STORAGE_PATH=${STORAGE_PATH}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
TS=${TS}"

  mkdir -p "$STORAGE_PATH"

  start_service "filebrowser"

  config_app_set filebrowser installed    true
  config_app_set filebrowser port         "$PORT"
  config_app_set filebrowser storage_path "$STORAGE_PATH"
  config_app_set filebrowser tailscale    "$TS"

  ok "Filebrowser running on port ${PORT}  →  http://localhost:${PORT}"
  info "Login with admin / <your chosen password>"
}

remove_filebrowser() {
  require_root
  header "Removing Filebrowser"
  remove_service_dir "filebrowser"
  config_app_set filebrowser installed false
  ok "Filebrowser removed."
}
```

- [ ] **Step 2: Verify bash syntax and shellcheck**

```bash
bash -n /Users/fabrizio/Projects/homekase/lib/services/filebrowser.sh && echo "syntax OK"
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/filebrowser.sh
```

Expected: `syntax OK`, no shellcheck output.

- [ ] **Step 3: Commit**

```bash
git add lib/services/filebrowser.sh
git commit -m "feat: add filebrowser service installer"
```

---

## Task 7: `lib/services/vikunja.sh`

**Files:**
- Create: `lib/services/vikunja.sh`

- [ ] **Step 1: Create `lib/services/vikunja.sh`**

```bash
#!/usr/bin/env bash
# Vikunja service installer (all-in-one with SQLite).
# Sourced by lib/services/service.sh on `homekase add vikunja`.

deploy_vikunja() {
  require_root
  header "Installing Vikunja"

  local PORT DATA_PATH TS

  PORT="$(port_wizard "vikunja" 1)"
  DATA_PATH="$(ask_input "Vikunja data path" "/data/config/vikunja")"
  TS="$(tailscale_serve_setup "$PORT")"

  write_service_dir "vikunja"

  write_compose_file "vikunja" "services:
  vikunja:
    image: vikunja/vikunja:latest
    container_name: vikunja
    restart: unless-stopped
    ports:
      - \"\${PORT}:3456\"
    volumes:
      - \${DATA_PATH}:/app/vikunja/files
    environment:
      VIKUNJA_DATABASE_TYPE: sqlite
      VIKUNJA_DATABASE_PATH: /app/vikunja/files/vikunja.db
      VIKUNJA_SERVICE_FRONTENDURL: http://localhost:\${PORT}
    networks:
      - homelab-net
    labels:
      com.homekase.service: vikunja
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: sqlite

networks:
  homelab-net:
    external: true"

  write_env_file "vikunja" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
TS=${TS}"

  mkdir -p "$DATA_PATH"

  start_service "vikunja"

  config_app_set vikunja installed  true
  config_app_set vikunja port       "$PORT"
  config_app_set vikunja data_path  "$DATA_PATH"
  config_app_set vikunja tailscale  "$TS"

  ok "Vikunja running on port ${PORT}  →  http://localhost:${PORT}"
}

remove_vikunja() {
  require_root
  header "Removing Vikunja"
  remove_service_dir "vikunja"
  config_app_set vikunja installed false
  ok "Vikunja removed."
}
```

- [ ] **Step 2: Verify bash syntax and shellcheck**

```bash
bash -n /Users/fabrizio/Projects/homekase/lib/services/vikunja.sh && echo "syntax OK"
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/vikunja.sh
```

Expected: `syntax OK`, no shellcheck output.

- [ ] **Step 3: Commit**

```bash
git add lib/services/vikunja.sh
git commit -m "feat: add vikunja service installer"
```

---

## Task 8: `lib/services/assistant.sh`

**Files:**
- Create: `lib/services/assistant.sh`

- [ ] **Step 1: Create `lib/services/assistant.sh`**

```bash
#!/usr/bin/env bash
# Local AI assistant service installer.
# Sourced by lib/services/service.sh on `homekase add assistant`.
# Clones git@github.com:FabriSilve/server-assistant.git, selects an Ollama
# model based on available RAM, then builds + starts via docker compose.

deploy_assistant() {
  require_root
  header "Installing Local AI Assistant"

  # ── RAM check ─────────────────────────────────────────────────────────────
  local ram_mb model
  ram_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
  if [[ -z "$ram_mb" ]]; then
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

  # ── Clone / update repo ───────────────────────────────────────────────────
  local ssh_key
  ssh_key="$(config_get 'ssh_key' 2>/dev/null || echo '/etc/homekase/.ssh/id_ed25519')"
  local REPO_DIR="/opt/homelab/assistant"

  if [[ -d "${REPO_DIR}/.git" ]]; then
    info "Updating server-assistant repo..."
    GIT_SSH_COMMAND="ssh -i ${ssh_key} -o StrictHostKeyChecking=accept-new" \
      git -C "$REPO_DIR" pull --ff-only
  else
    info "Cloning server-assistant repo..."
    mkdir -p "$(dirname "$REPO_DIR")"
    GIT_SSH_COMMAND="ssh -i ${ssh_key} -o StrictHostKeyChecking=accept-new" \
      git clone git@github.com:FabriSilve/server-assistant.git "$REPO_DIR"
  fi

  # ── Port + Tailscale ──────────────────────────────────────────────────────
  local PORT TS
  PORT="$(port_wizard "assistant" 1)"
  TS="$(tailscale_serve_setup "$PORT")"

  # ── Write .env ────────────────────────────────────────────────────────────
  write_env_file "assistant" "PORT=${PORT}
OLLAMA_MODEL=${model}
TS=${TS}"

  # ── Build + start ─────────────────────────────────────────────────────────
  info "Building assistant image (this may take a few minutes)..."
  docker compose -f "${REPO_DIR}/docker-compose.yml" build

  info "Starting assistant..."
  docker compose -f "${REPO_DIR}/docker-compose.yml" up -d

  # ── Pull the Ollama model ─────────────────────────────────────────────────
  info "Pulling Ollama model ${model} (large download — be patient)..."
  docker exec ollama ollama pull "$model"

  # ── Config ────────────────────────────────────────────────────────────────
  config_app_set assistant installed true
  config_app_set assistant port      "$PORT"
  config_app_set assistant tailscale "$TS"

  ok "Assistant running on port ${PORT}  →  http://localhost:${PORT}"
  info "Model: ${model}"
}

remove_assistant() {
  require_root
  header "Removing Local AI Assistant"
  remove_service_dir "assistant"
  config_app_set assistant installed false
  ok "Assistant removed."
}
```

- [ ] **Step 2: Verify bash syntax and shellcheck**

```bash
bash -n /Users/fabrizio/Projects/homekase/lib/services/assistant.sh && echo "syntax OK"
shellcheck -x /Users/fabrizio/Projects/homekase/lib/services/assistant.sh
```

Expected: `syntax OK`, no shellcheck output.

- [ ] **Step 3: Commit**

```bash
git add lib/services/assistant.sh
git commit -m "feat: add assistant service installer with RAM-gated model selection"
```

---

## Task 9: Final integration check

**Files:**
- No new files — verify everything hangs together.

- [ ] **Step 1: Run the full test suite**

```bash
cd /Users/fabrizio/Projects/homekase && make check
```

Expected:
```
:: ShellCheck...
  ✓ ./homekase
  ✓ ./lib/common.sh
  ✓ ./lib/config.sh
  ✓ ./lib/services/_common.sh
  ✓ ./lib/services/service.sh
  ✓ ./lib/services/jellyfin.sh
  ✓ ./lib/services/immich.sh
  ✓ ./lib/services/qbittorrent.sh
  ✓ ./lib/services/filebrowser.sh
  ✓ ./lib/services/vikunja.sh
  ✓ ./lib/services/assistant.sh
  [... other files ...]
:: Bash syntax...
  [same list, all ✓]
:: Bats unit tests...
  [all tests pass]
✓ All checks passed
```

- [ ] **Step 2: Smoke-test the list command without Docker**

```bash
HOMEKASE_CONFIG="$(mktemp)" && \
  cp /Users/fabrizio/Projects/homekase/templates/homekase.yml.template "$HOMEKASE_CONFIG" && \
  HOMEKASE_CONFIG="$HOMEKASE_CONFIG" \
  HOMEKASE_DIR="/Users/fabrizio/Projects/homekase" \
  bash /Users/fabrizio/Projects/homekase/homekase list
```

Expected: a table with all six service names, status "not installed" for each.

- [ ] **Step 3: Mark an app installed and verify list shows it**

```bash
TMP_CFG="$(mktemp)" && \
  cp /Users/fabrizio/Projects/homekase/templates/homekase.yml.template "$TMP_CFG" && \
  HOMEKASE_CONFIG="$TMP_CFG" bash -c '
    source /Users/fabrizio/Projects/homekase/lib/config.sh
    config_app_set jellyfin installed true
    config_app_set jellyfin port 4000
    config_app_set jellyfin tailscale false
  ' && \
  HOMEKASE_CONFIG="$TMP_CFG" \
  HOMEKASE_DIR="/Users/fabrizio/Projects/homekase" \
  bash /Users/fabrizio/Projects/homekase/homekase list
```

Expected: jellyfin row shows "installed" and port "4000".

- [ ] **Step 4: Verify unknown service exits 1**

```bash
HOMEKASE_CONFIG="$(mktemp)" && \
  cp /Users/fabrizio/Projects/homekase/templates/homekase.yml.template "$HOMEKASE_CONFIG" && \
  HOMEKASE_CONFIG="$HOMEKASE_CONFIG" \
  HOMEKASE_DIR="/Users/fabrizio/Projects/homekase" \
  bash /Users/fabrizio/Projects/homekase/homekase add __bogus__ ; echo "exit: $?"
```

Expected: output contains "Unknown service", exit code 1.

- [ ] **Step 5: Commit**

```bash
git add -p   # review; nothing new should be staged
# If all clean, no commit needed.
# If any fixes were made during smoke tests, commit them:
git commit -m "fix: smoke test corrections in services"
```

---

## Self-Review

### 1. Spec Coverage

| Spec requirement | Task covering it |
|---|---|
| `cmd_list` reads registry + checks `config_app_installed` → table | Task 2 |
| Table columns: Name, Description, Status, Port, URL | Task 2 `cmd_list` |
| `cmd_add <name>` sources `lib/services/<name>.sh`, calls `deploy_<name>` | Task 2 |
| `cmd_remove <name>` sources file, calls `remove_<name>` | Task 2 |
| Service registry array (6 services) | Task 2 `SERVICES=()` |
| `next_available_port` reads all `apps.*.port`, returns max+10 | Task 1 |
| `port_wizard` shows suggestion, validates via `ss`, returns port | Task 1 |
| `tailscale_serve_setup` checks config, ask_confirm, runs `tailscale serve` | Task 1 |
| `write_service_dir`, `write_env_file`, `write_compose_file`, `start_service`, `stop_service`, `remove_service_dir` | Task 1 |
| jellyfin deploy: port, data_path, media_path, compose, env, mkdir, start, config | Task 3 |
| jellyfin Docker labels (all 6 label keys) | Task 3 |
| jellyfin remove: stop + remove_service_dir + config | Task 3 |
| immich deploy: 4 containers, DB password, env_file, labels | Task 4 |
| immich remove | Task 4 |
| qbittorrent deploy: optional VPN (gluetun), two compose variants | Task 5 |
| qbittorrent remove | Task 5 |
| filebrowser deploy: port, storage, admin password, compose | Task 6 |
| filebrowser remove | Task 6 |
| vikunja deploy: SQLite all-in-one, port, data_path | Task 7 |
| vikunja remove | Task 7 |
| assistant: RAM check → model select, git clone/pull, build, pull model | Task 8 |
| assistant remove | Task 8 |
| `tests/test_services.bats` — cmd_list exits 0 | Task 2 |
| `tests/test_services.bats` — cmd_list contains each service name | Task 2 |
| `tests/test_services.bats` — next_available_port returns numeric | Task 1 |
| `tests/test_services.bats` — cmd_add unknown exits 1 with error | Task 2 |
| `tests/test_services.bats` — cmd_remove unknown exits 1 | Task 2 |

All requirements covered.

### 2. Placeholder scan

No "TBD", "TODO", or vague instructions. Every step has exact code or exact commands with expected output.

### 3. Type/name consistency

- `next_available_port` — defined in Task 1, called by `port_wizard` in Task 1, both in `_common.sh`. Consistent.
- `port_wizard` — defined Task 1, called in Tasks 3–8 as `port_wizard "name" N`. Consistent.
- `tailscale_serve_setup` — defined Task 1, called in Tasks 3–8 as `tailscale_serve_setup "$PORT"`. Consistent.
- `write_service_dir`, `write_env_file`, `write_compose_file` — defined Task 1, called with `(name, content)` in Tasks 3–8. Consistent.
- `start_service`, `stop_service`, `remove_service_dir` — defined Task 1, called with `(name)` in Tasks 3–8. Consistent.
- `config_app_set`, `config_app_get`, `config_app_installed` — imported from `lib/config.sh` (not defined here). All callers use the three-argument form `config_app_set <app> <key> <value>` which matches the existing definition in `lib/config.sh:34`. Consistent.
- `deploy_<name>` / `remove_<name>` — function names in each service file match the `"deploy_${name}"` / `"remove_${name}"` dynamic dispatch in `service.sh`. Consistent.
- `HOMEKASE_DIR` — set in `homekase` entry point, exported; used in `service.sh` to source `_common.sh` and the per-service files. `_common.sh` uses `HOMELAB_DIR` (separate variable for `/opt/homelab`). No collision.
