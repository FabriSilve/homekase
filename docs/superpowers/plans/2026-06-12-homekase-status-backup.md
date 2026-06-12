# homekase CLI — Plan 5: Status + Backup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two stub files `lib/status.sh` and `lib/backup.sh` with full implementations. `homekase status` collects system metrics, disk usage, and Docker service state, then pretty-prints or outputs JSON. `homekase backup [app] [--incremental]` snapshots app data volumes and databases, with cron-safe locking and incremental rsync support.

**Architecture:** Both commands are sourced on-demand by `homekase` (main entry point) and follow the existing pattern: source `lib/common.sh` + `lib/config.sh` for logging and YAML config access; query Docker labels directly via `docker inspect` / `docker ps --format`; never read `homekase.yml` app keys for backup metadata (use container labels instead, which are the authoritative source from Plan 4). `lib/status.sh` builds data into local bash variables first, then either pretty-prints with `header()` / formatted `printf` or assembles JSON with `jq -n`. `lib/backup.sh` uses a lockfile at `/tmp/homekase-backup.lock` to prevent overlapping cron runs.

**Tech Stack:** bash 5+, Docker Engine (docker CLI), jq (JSON assembly and output), rsync (incremental backups), yq v4 (config reads via `config_get`), bats-core (tests)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/status.sh` | REPLACE stub | `cmd_status [--json]` — system, disk, service state |
| `lib/backup.sh` | REPLACE stub | `cmd_backup [app] [--incremental]` — snapshot + incremental |
| `tests/test_status.bats` | CREATE | bats tests for status command |
| `tests/test_backup.bats` | CREATE | bats tests for backup command |

No other files change. The main `homekase` entry point already dispatches to both commands (see lines 67–68 of `homekase`).

---

## Task 1: lib/status.sh — TDD

**Files:** `lib/status.sh` (replace), `tests/test_status.bats` (create)

### Step 1: Write failing tests

- [ ] Create `tests/test_status.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

# Build a fake docker binary that returns predictable label output
setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"

  # Temp dir for fake binaries and config
  FAKE_BIN="$(mktemp -d)"
  export FAKE_BIN

  # Fake docker: handles the two calls cmd_status makes:
  #   docker ps --filter label=com.homekase.service --format '{{.Names}}'
  #   docker inspect <name> --format '{{index .Config.Labels "..."}}
  cat > "$FAKE_BIN/docker" <<'FAKE'
#!/usr/bin/env bash
if [[ "$*" == *"--filter"*"com.homekase.service"*"--format"*"{{.Names}}"* ]]; then
  echo "jellyfin"
elif [[ "$*" == *"inspect"*"--format"*"com.homekase.service"* ]]; then
  echo "jellyfin"
elif [[ "$*" == *"inspect"*"--format"*"com.homekase.port"* ]]; then
  echo "8096"
elif [[ "$*" == *"inspect"*"--format"*"com.homekase.tailscale"* ]]; then
  echo "false"
elif [[ "$*" == *"inspect"*"--format"*"{{.State.Running}}"* ]]; then
  echo "true"
else
  echo ""
fi
FAKE
  chmod +x "$FAKE_BIN/docker"

  # Minimal config so config_get tailscale.hostname works
  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test-XXXXX.yml)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG

  PATH="$FAKE_BIN:$PATH"
  export PATH
}

teardown() {
  rm -rf "$FAKE_BIN"
  rm -f "$HOMEKASE_CONFIG"
}

@test "cmd_status exits 0" {
  source "$PROJECT_ROOT/lib/status.sh"
  run cmd_status
  [ "$status" -eq 0 ]
}

@test "cmd_status --json exits 0" {
  source "$PROJECT_ROOT/lib/status.sh"
  run cmd_status --json
  [ "$status" -eq 0 ]
}

@test "cmd_status --json output is valid JSON" {
  source "$PROJECT_ROOT/lib/status.sh"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    cmd_status --json
  "
  [ "$status" -eq 0 ]
  echo "$output" | jq . > /dev/null
}

@test "cmd_status --json system section includes hostname" {
  source "$PROJECT_ROOT/lib/status.sh"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    cmd_status --json
  "
  [ "$status" -eq 0 ]
  hostname_val="$(echo "$output" | jq -r '.system.hostname')"
  [ -n "$hostname_val" ]
  [ "$hostname_val" != "null" ]
}

@test "cmd_status pretty output contains System section" {
  source "$PROJECT_ROOT/lib/status.sh"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    cmd_status
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"System"* ]]
}

@test "cmd_status pretty output contains Services section" {
  source "$PROJECT_ROOT/lib/status.sh"
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/status.sh'
    cmd_status
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Services"* ]]
}
```

### Step 2: Run — expect failure

- [ ] Run tests, confirm they fail because the stub returns before collecting data:

```bash
bats tests/test_status.bats
```

Expected output (partial):
```
 ✓ cmd_status exits 0        ← stub exits 0, this test passes
 ✗ cmd_status --json exits 0
 ✗ cmd_status --json output is valid JSON
 ✗ cmd_status --json system section includes hostname
 ✗ cmd_status pretty output contains System section
 ✗ cmd_status pretty output contains Services section
5 tests, 4 failures (or similar)
```

### Step 3: Implement lib/status.sh

- [ ] Replace `lib/status.sh` with the full implementation:

```bash
#!/usr/bin/env bash
# lib/status.sh — homekase status [--json]
# Collects system metrics, disk usage, and Docker service state.
# Outputs pretty-printed table (default) or structured JSON (--json).

# ---------------------------------------------------------------------------
# _status_collect_system
# Sets globals: _hn, _uptime, _load1, _load5, _load15, _ram_used_mb, _ram_total_mb, _os_name
# ---------------------------------------------------------------------------
_status_collect_system() {
  _hn="$(hostname)"

  # Uptime — parse /proc/uptime (seconds since boot)
  local up_sec
  up_sec="$(awk '{print int($1)}' /proc/uptime)"
  local days=$(( up_sec / 86400 ))
  local hours=$(( (up_sec % 86400) / 3600 ))
  local mins=$(( (up_sec % 3600) / 60 ))
  if (( days > 0 )); then
    _uptime="${days} day$([ "$days" -ne 1 ] && echo s), ${hours} hour$([ "$hours" -ne 1 ] && echo s)"
  elif (( hours > 0 )); then
    _uptime="${hours} hour$([ "$hours" -ne 1 ] && echo s), ${mins} min$([ "$mins" -ne 1 ] && echo s)"
  else
    _uptime="${mins} min$([ "$mins" -ne 1 ] && echo s)"
  fi

  # Load averages from /proc/loadavg
  read -r _load1 _load5 _load15 _ _ < /proc/loadavg

  # RAM via free -m: second line is Mem, columns: total used free shared buff/cache available
  local mem_line
  mem_line="$(free -m | awk 'NR==2 {print $2, $3}')"
  _ram_total_mb="${mem_line%% *}"
  _ram_used_mb="${mem_line##* }"

  # OS name
  _os_name="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
}

# ---------------------------------------------------------------------------
# _status_collect_disk
# Populates parallel arrays: _disk_mount[] _disk_used[] _disk_total[] _disk_pct[]
# Only includes mounts that exist: /data /storage /backup
# ---------------------------------------------------------------------------
_status_collect_disk() {
  _disk_mount=()
  _disk_used=()
  _disk_total=()
  _disk_pct=()

  local mounts=(/data /storage /backup)
  local m
  for m in "${mounts[@]}"; do
    [[ -d "$m" ]] || continue
    # df -h --output=size,used,pcent,target — skip header (NR>1)
    local line
    line="$(df -h --output=size,used,pcent,target "$m" 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $4}')"
    [[ -z "$line" ]] && continue
    local total used pct target
    read -r total used pct target <<< "$line"
    _disk_mount+=("$target")
    _disk_used+=("$used")
    _disk_total+=("$total")
    _disk_pct+=("$pct")
  done
}

# ---------------------------------------------------------------------------
# _status_collect_services
# Populates parallel arrays: _svc_name[] _svc_port[] _svc_running[] _svc_url[]
# Reads containers with label com.homekase.service via docker ps + docker inspect.
# ---------------------------------------------------------------------------
_status_collect_services() {
  _svc_name=()
  _svc_port=()
  _svc_running=()
  _svc_url=()

  local ts_hostname
  ts_hostname="$(config_get 'tailscale.hostname' 2>/dev/null || true)"

  # Get all container names carrying the homekase.service label (running or stopped)
  local containers
  containers="$(docker ps -a \
    --filter "label=com.homekase.service" \
    --format '{{.Names}}' 2>/dev/null || true)"

  [[ -z "$containers" ]] && return 0

  local cname
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue

    local svc port ts_flag running url
    svc="$(docker inspect "$cname" --format '{{index .Config.Labels "com.homekase.service"}}' 2>/dev/null || true)"
    port="$(docker inspect "$cname" --format '{{index .Config.Labels "com.homekase.port"}}' 2>/dev/null || true)"
    ts_flag="$(docker inspect "$cname" --format '{{index .Config.Labels "com.homekase.tailscale"}}' 2>/dev/null || true)"
    running="$(docker inspect "$cname" --format '{{.State.Running}}' 2>/dev/null || true)"

    url="null"
    if [[ "$ts_flag" == "true" && -n "$ts_hostname" && "$ts_hostname" != "null" && -n "$port" ]]; then
      url="https://${ts_hostname}:${port}"
    fi

    _svc_name+=("$svc")
    _svc_port+=("$port")
    _svc_running+=("$running")
    _svc_url+=("$url")
  done <<< "$containers"
}

# ---------------------------------------------------------------------------
# cmd_status [--json]
# ---------------------------------------------------------------------------
cmd_status() {
  local json_mode=false
  for arg in "$@"; do
    [[ "$arg" == "--json" ]] && json_mode=true
  done

  # Collect all data
  _status_collect_system
  _status_collect_disk
  _status_collect_services

  # ---- JSON output -------------------------------------------------------
  if $json_mode; then
    # Build disk array
    local disk_json="[]"
    local i
    for i in "${!_disk_mount[@]}"; do
      disk_json="$(jq -n \
        --argjson arr "$disk_json" \
        --arg mount "${_disk_mount[$i]}" \
        --arg used  "${_disk_used[$i]}" \
        --arg total "${_disk_total[$i]}" \
        --arg pct   "${_disk_pct[$i]}" \
        '$arr + [{"mount":$mount,"used":$used,"total":$total,"percent":$pct}]')"
    done

    # Build services array
    local svc_json="[]"
    for i in "${!_svc_name[@]}"; do
      local url_val
      if [[ "${_svc_url[$i]}" == "null" ]]; then
        url_val="null"
      else
        url_val="\"${_svc_url[$i]}\""
      fi
      local running_bool="false"
      [[ "${_svc_running[$i]}" == "true" ]] && running_bool="true"
      local port_int="${_svc_port[$i]:-0}"
      svc_json="$(jq -n \
        --argjson arr "$svc_json" \
        --arg  name    "${_svc_name[$i]}" \
        --argjson port  "${port_int:-0}" \
        --argjson run   "$running_bool" \
        --argjson url   "$url_val" \
        '$arr + [{"name":$name,"port":$port,"running":$run,"url":$url}]')"
    done

    jq -n \
      --arg  hostname   "$_hn" \
      --arg  uptime     "$_uptime" \
      --arg  load1      "$_load1" \
      --arg  load5      "$_load5" \
      --arg  load15     "$_load15" \
      --argjson ram_used  "${_ram_used_mb:-0}" \
      --argjson ram_total "${_ram_total_mb:-0}" \
      --argjson disk      "$disk_json" \
      --argjson services  "$svc_json" \
      '{
        system: {
          hostname:  $hostname,
          uptime:    $uptime,
          load:      {"1m": $load1, "5m": $load5, "15m": $load15},
          ram:       {"used_mb": $ram_used, "total_mb": $ram_total}
        },
        disk:     $disk,
        services: $services
      }'
    return 0
  fi

  # ---- Pretty-print output -----------------------------------------------
  header "System"
  printf "  %-12s %s\n" "Hostname:"  "$_hn"
  printf "  %-12s %s\n" "Uptime:"    "$_uptime"
  printf "  %-12s %s / %s / %s\n" "Load:" "$_load1" "$_load5" "$_load15"
  # Format RAM as G with one decimal if >= 1024MB, else MB
  local ram_used_disp ram_total_disp
  if (( _ram_total_mb >= 1024 )); then
    ram_used_disp="$(awk "BEGIN{printf \"%.1fG\", ${_ram_used_mb}/1024}")"
    ram_total_disp="$(awk "BEGIN{printf \"%.1fG\", ${_ram_total_mb}/1024}")"
  else
    ram_used_disp="${_ram_used_mb}M"
    ram_total_disp="${_ram_total_mb}M"
  fi
  printf "  %-12s %s / %s used\n" "RAM:" "$ram_used_disp" "$ram_total_disp"

  if (( ${#_disk_mount[@]} > 0 )); then
    header "Disk"
    local i
    for i in "${!_disk_mount[@]}"; do
      printf "  %-12s %s used of %s (%s)\n" \
        "${_disk_mount[$i]}" "${_disk_used[$i]}" "${_disk_total[$i]}" "${_disk_pct[$i]}"
    done
  fi

  header "Services"
  if (( ${#_svc_name[@]} == 0 )); then
    printf "  (no homekase services running)\n"
  else
    local i
    for i in "${!_svc_name[@]}"; do
      local sym url_part
      if [[ "${_svc_running[$i]}" == "true" ]]; then
        sym="${GREEN}●${RESET}"
        status_word="running"
      else
        sym="${RED}○${RESET}"
        status_word="stopped"
      fi
      url_part=""
      [[ "${_svc_url[$i]}" != "null" && -n "${_svc_url[$i]}" ]] && url_part="   ${_svc_url[$i]}"
      printf "  %-14s %b %-10s :%s%s\n" \
        "${_svc_name[$i]}" "$sym" "$status_word" "${_svc_port[$i]}" "$url_part"
    done
  fi
  echo
}
```

### Step 4: Run — expect pass

- [ ] Run the test suite:

```bash
bats tests/test_status.bats
```

Expected:
```
 ✓ cmd_status exits 0
 ✓ cmd_status --json exits 0
 ✓ cmd_status --json output is valid JSON
 ✓ cmd_status --json system section includes hostname
 ✓ cmd_status pretty output contains System section
 ✓ cmd_status pretty output contains Services section
6 tests, 0 failures
```

### Step 5: Manual smoke test

- [ ] Verify pretty output on the server (or dev machine):

```bash
bash homekase status
```

Expected (example):
```

▶ System

  Hostname:    myserver
  Uptime:      2 days, 4 hours
  Load:        0.12 / 0.15 / 0.18
  RAM:         3.2G / 15.5G used

▶ Disk

  /data        50G used of 200G (25%)
  /storage     120G used of 500G (24%)

▶ Services

  jellyfin       ● running    :8096   https://myserver.tail1234.ts.net:8096
  vikunja        ○ stopped    :3456

```

- [ ] Verify JSON output:

```bash
bash homekase status --json | jq .
```

Expected (structure):
```json
{
  "system": {
    "hostname": "myserver",
    "uptime": "2 days, 4 hours",
    "load": { "1m": "0.12", "5m": "0.15", "15m": "0.18" },
    "ram": { "used_mb": 3276, "total_mb": 15872 }
  },
  "disk": [
    { "mount": "/data", "used": "50G", "total": "200G", "percent": "25%" }
  ],
  "services": [
    { "name": "jellyfin", "port": 8096, "running": true, "url": "https://myserver.tail1234.ts.net:8096" },
    { "name": "vikunja",  "port": 3456, "running": false, "url": null }
  ]
}
```

### Step 6: ShellCheck

- [ ] Run ShellCheck on the new file:

```bash
shellcheck -x lib/status.sh
```

Expected: no output (zero errors). If any SC2206/SC2207 warnings appear about array assignment, address by quoting array reads. Common fix for `read -r` into array:

```bash
# If shellcheck flags read -r _load1 _load5 _load15:
# Suppress with: # shellcheck disable=SC2034
# Or use mapfile for arrays — but scalar reads are fine here
```

### Step 7: Commit

- [ ] Stage and commit:

```bash
git add lib/status.sh tests/test_status.bats
git commit -m "feat: implement homekase status with system/disk/service display and --json flag"
```

---

## Task 2: lib/backup.sh — TDD

**Files:** `lib/backup.sh` (replace), `tests/test_backup.bats` (create)

### Step 1: Write failing tests

- [ ] Create `tests/test_backup.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"

  FAKE_BIN="$(mktemp -d)"
  FAKE_BACKUP_DIR="$(mktemp -d)"
  export FAKE_BIN FAKE_BACKUP_DIR

  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test-XXXXX.yml)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  # Override backup path to writable temp dir
  yq -i ".paths.backup = \"$FAKE_BACKUP_DIR\"" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG

  # Fake docker: returns no containers for unknown apps; for "testapp" returns one container
  cat > "$FAKE_BIN/docker" <<'FAKE'
#!/usr/bin/env bash
# Called as: docker ps -a --filter label=com.homekase.service=<app> --format {{.Names}}
if [[ "$*" == *"com.homekase.service=testapp"* && "$*" == *"{{.Names}}"* ]]; then
  echo "testapp_app_1"
elif [[ "$*" == *"com.homekase.service="* && "$*" == *"{{.Names}}"* ]]; then
  echo ""
# Called as: docker inspect <cname> --format {{index .Config.Labels "..."}}
elif [[ "$*" == *"inspect"*"backup.type"* ]]; then
  echo "snapshot"
elif [[ "$*" == *"inspect"*"backup.data"* ]]; then
  echo "/tmp"
elif [[ "$*" == *"inspect"*"backup.storage"* ]]; then
  echo ""
elif [[ "$*" == *"inspect"*"backup.db-type"* ]]; then
  echo "none"
# docker ps --filter label=com.homekase.service --format {{.Names}} (all services)
elif [[ "$*" == *"com.homekase.service"* && "$*" == *"{{.Names}}"* ]]; then
  echo ""
else
  echo ""
fi
FAKE
  chmod +x "$FAKE_BIN/docker"

  # Fake rsync for incremental tests
  cat > "$FAKE_BIN/rsync" <<'FAKE'
#!/usr/bin/env bash
echo "rsync called: $*"
exit 0
FAKE
  chmod +x "$FAKE_BIN/rsync"

  # Fake tar that creates an empty file so test can verify file presence
  cat > "$FAKE_BIN/tar" <<'FAKE'
#!/usr/bin/env bash
# Find -f argument and touch it so the test can assert it exists
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-f" ]]; then
    touch "$arg"
  fi
  prev="$arg"
done
exit 0
FAKE
  chmod +x "$FAKE_BIN/tar"

  PATH="$FAKE_BIN:$PATH"
  export PATH

  # Remove any stale lockfile
  rm -f /tmp/homekase-backup.lock
}

teardown() {
  rm -rf "$FAKE_BIN" "$FAKE_BACKUP_DIR"
  rm -f "$HOMEKASE_CONFIG"
  rm -f /tmp/homekase-backup.lock
}

@test "cmd_backup unknown app exits 1 with error message" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup unknown_app_xyz
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown_app_xyz"* ]]
}

@test "cmd_backup with no apps exits 0 with nothing-to-backup message" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing"* || "$output" == *"no services"* || "$output" == *"Nothing"* ]]
}

@test "cmd_backup testapp creates destination directory" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp
  "
  [ "$status" -eq 0 ]
  # A timestamped sub-directory under FAKE_BACKUP_DIR/testapp/ must exist
  local found
  found="$(find "$FAKE_BACKUP_DIR/testapp" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
  [ -n "$found" ]
}

@test "cmd_backup testapp snapshot creates data.tar.gz" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp
  "
  [ "$status" -eq 0 ]
  local found
  found="$(find "$FAKE_BACKUP_DIR/testapp" -name 'data.tar.gz' 2>/dev/null | head -1)"
  [ -n "$found" ]
}

@test "cmd_backup --incremental testapp calls rsync not tar" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp --incremental
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"rsync called"* ]]
}

@test "cmd_backup testapp writes to backup.log" {
  run bash -c "
    source '$PROJECT_ROOT/lib/common.sh'
    source '$PROJECT_ROOT/lib/config.sh'
    export HOMEKASE_CONFIG='$HOMEKASE_CONFIG'
    export PATH='$FAKE_BIN:\$PATH'
    source '$PROJECT_ROOT/lib/backup.sh'
    cmd_backup testapp
  "
  [ "$status" -eq 0 ]
  [ -f "$FAKE_BACKUP_DIR/backup.log" ]
}
```

### Step 2: Run — expect failure

- [ ] Run tests, confirm stub does not implement any backup logic:

```bash
bats tests/test_backup.bats
```

Expected: most tests fail. The "unknown app exits 1" test may pass if stub exits with a warning, but "creates destination directory" will fail.

### Step 3: Implement lib/backup.sh

- [ ] Replace `lib/backup.sh` with the full implementation:

```bash
#!/usr/bin/env bash
# lib/backup.sh — homekase backup [app-name] [--incremental]
# Snapshots app data + databases. Cron-safe (exits 0 if nothing to do).
# Lock at /tmp/homekase-backup.lock prevents overlapping runs.

BACKUP_LOCK="/tmp/homekase-backup.lock"
BACKUP_LOG=""   # set after config is loaded

# ---------------------------------------------------------------------------
# _backup_acquire_lock
# Exits 1 if another backup is already running.
# ---------------------------------------------------------------------------
_backup_acquire_lock() {
  if [[ -e "$BACKUP_LOCK" ]]; then
    local pid
    pid="$(cat "$BACKUP_LOCK" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      error "Another homekase backup is already running (PID $pid). Exiting."
      exit 1
    fi
    # Stale lock — remove it
    rm -f "$BACKUP_LOCK"
  fi
  echo "$$" > "$BACKUP_LOCK"
}

_backup_release_lock() {
  rm -f "$BACKUP_LOCK"
}

# ---------------------------------------------------------------------------
# _backup_log <message>
# Appends timestamped line to backup.log
# ---------------------------------------------------------------------------
_backup_log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$ts] $*" >> "$BACKUP_LOG"
}

# ---------------------------------------------------------------------------
# _backup_get_label <container> <label>
# Returns the value of a Docker label, or empty string.
# ---------------------------------------------------------------------------
_backup_get_label() {
  local cname="$1" label="$2"
  docker inspect "$cname" --format "{{index .Config.Labels \"$label\"}}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# _backup_get_env <container> <VAR_PREFIX>
# Returns the value of an env var inside the container matching prefix.
# E.g. _backup_get_env mycontainer POSTGRES_USER
# ---------------------------------------------------------------------------
_backup_get_env() {
  local cname="$1" varname="$2"
  docker inspect "$cname" \
    --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep "^${varname}=" \
    | head -1 \
    | cut -d= -f2- \
    || true
}

# ---------------------------------------------------------------------------
# _backup_dump_db <container> <db_type> <dest_dir>
# Dumps the database to $dest_dir/db.sql (postgres/mysql) or $dest_dir/mongodump/
# No-op if db_type is "none" or empty.
# ---------------------------------------------------------------------------
_backup_dump_db() {
  local cname="$1" db_type="$2" dest="$3"

  case "$db_type" in
    postgres)
      local pg_user pg_db
      pg_user="$(_backup_get_env "$cname" POSTGRES_USER)"
      pg_db="$(_backup_get_env "$cname" POSTGRES_DB)"
      info "Dumping PostgreSQL database ($pg_db)..."
      docker exec "$cname" pg_dump -U "$pg_user" "$pg_db" > "$dest/db.sql"
      ok "pg_dump written to $dest/db.sql"
      ;;
    mysql)
      local mysql_user mysql_pass mysql_db
      mysql_user="$(_backup_get_env "$cname" MYSQL_USER)"
      mysql_pass="$(_backup_get_env "$cname" MYSQL_PASSWORD)"
      mysql_db="$(_backup_get_env "$cname" MYSQL_DATABASE)"
      info "Dumping MySQL database ($mysql_db)..."
      docker exec "$cname" mysqldump -u "$mysql_user" -p"$mysql_pass" "$mysql_db" > "$dest/db.sql"
      ok "mysqldump written to $dest/db.sql"
      ;;
    mongodb)
      info "Dumping MongoDB..."
      docker exec "$cname" mongodump --out /tmp/mongodump
      docker cp "$cname:/tmp/mongodump" "$dest/mongodump"
      ok "mongodump written to $dest/mongodump/"
      ;;
    none|"")
      # No database — nothing to do
      ;;
    *)
      warn "Unknown db-type '$db_type' for container $cname — skipping DB dump"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _backup_snapshot <app> <container>
# Full snapshot: db dump + tar of data path (+ storage path if set).
# ---------------------------------------------------------------------------
_backup_snapshot() {
  local app="$1" cname="$2"

  local backup_type backup_data backup_storage db_type
  backup_type="$(_backup_get_label "$cname" "com.homekase.backup.type")"
  backup_data="$(_backup_get_label "$cname" "com.homekase.backup.data")"
  backup_storage="$(_backup_get_label "$cname" "com.homekase.backup.storage")"
  db_type="$(_backup_get_label "$cname" "com.homekase.backup.db-type")"

  local date_tag
  date_tag="$(date +%Y%m%d-%H%M%S)"
  local dest="${BACKUP_LOG%/backup.log}/${app}/${date_tag}"
  mkdir -p "$dest"

  info "Backing up $app → $dest"

  # 1. Database dump (always fresh even in snapshot mode)
  _backup_dump_db "$cname" "$db_type" "$dest"

  # 2. Data volume
  if [[ -n "$backup_data" ]]; then
    info "Archiving data: $backup_data"
    tar -czf "$dest/data.tar.gz" -C / "${backup_data#/}"
    ok "data.tar.gz written"
  fi

  # 3. Storage volume (optional)
  if [[ -n "$backup_storage" && "$backup_storage" != "null" ]]; then
    info "Archiving storage: $backup_storage"
    tar -czf "$dest/storage.tar.gz" -C / "${backup_storage#/}"
    ok "storage.tar.gz written"
  fi

  _backup_log "OK  $app  snapshot  $dest"
  ok "Backed up $app to $dest"
}

# ---------------------------------------------------------------------------
# _backup_incremental <app> <container>
# Incremental: rsync --link-dest from previous snapshot; DB still fully dumped.
# ---------------------------------------------------------------------------
_backup_incremental() {
  local app="$1" cname="$2"

  local backup_data backup_storage db_type
  backup_data="$(_backup_get_label "$cname" "com.homekase.backup.data")"
  backup_storage="$(_backup_get_label "$cname" "com.homekase.backup.storage")"
  db_type="$(_backup_get_label "$cname" "com.homekase.backup.db-type")"

  local app_backup_dir="${BACKUP_LOG%/backup.log}/${app}"
  local date_tag
  date_tag="$(date +%Y%m%d-%H%M%S)"
  local dest="${app_backup_dir}/${date_tag}"
  mkdir -p "$dest"

  info "Incremental backup of $app → $dest"

  # Find the most recent previous snapshot directory (sorted, last entry)
  local prev_dest=""
  if [[ -d "$app_backup_dir" ]]; then
    prev_dest="$(find "$app_backup_dir" -mindepth 1 -maxdepth 1 -type d \
      ! -name "$date_tag" \
      | sort \
      | tail -1 || true)"
  fi

  # 1. Database dump — always full SQL dump even for incremental
  _backup_dump_db "$cname" "$db_type" "$dest"

  # 2. Data via rsync with hardlinks to previous snapshot
  if [[ -n "$backup_data" ]]; then
    mkdir -p "$dest/data"
    local link_dest_arg=""
    if [[ -n "$prev_dest" && -d "$prev_dest/data" ]]; then
      link_dest_arg="--link-dest=$prev_dest/data"
      info "Using previous snapshot for hardlinks: $prev_dest/data"
    fi
    info "Rsyncing data: $backup_data"
    # shellcheck disable=SC2086
    rsync -a $link_dest_arg "$backup_data/" "$dest/data/"
    ok "data/ synced"
  fi

  # 3. Storage via rsync (optional)
  if [[ -n "$backup_storage" && "$backup_storage" != "null" ]]; then
    mkdir -p "$dest/storage"
    local link_dest_arg=""
    if [[ -n "$prev_dest" && -d "$prev_dest/storage" ]]; then
      link_dest_arg="--link-dest=$prev_dest/storage"
    fi
    info "Rsyncing storage: $backup_storage"
    # shellcheck disable=SC2086
    rsync -a $link_dest_arg "$backup_storage/" "$dest/storage/"
    ok "storage/ synced"
  fi

  _backup_log "OK  $app  incremental  $dest"
  ok "Incremental backup of $app to $dest"
}

# ---------------------------------------------------------------------------
# _backup_one_app <app> <incremental: true|false>
# Locates the container, checks backup.type label, dispatches to snapshot or
# incremental. Returns 1 if app not found.
# ---------------------------------------------------------------------------
_backup_one_app() {
  local app="$1" incremental="$2"

  # Find container name for this app (may be running or stopped)
  local cname
  cname="$(docker ps -a \
    --filter "label=com.homekase.service=${app}" \
    --format '{{.Names}}' 2>/dev/null | head -1 || true)"

  if [[ -z "$cname" ]]; then
    error "No container found for service '$app'. Is it installed?"
    _backup_log "ERR $app  not found"
    return 1
  fi

  local backup_type
  backup_type="$(_backup_get_label "$cname" "com.homekase.backup.type")"

  if [[ "$backup_type" == "none" || -z "$backup_type" ]]; then
    info "$app: backup.type=none — skipping"
    return 0
  fi

  if $incremental; then
    _backup_incremental "$app" "$cname"
  else
    _backup_snapshot "$app" "$cname"
  fi
}

# ---------------------------------------------------------------------------
# cmd_backup [app-name] [--incremental]
# Entry point called by the main homekase dispatcher.
# ---------------------------------------------------------------------------
cmd_backup() {
  local app_arg=""
  local incremental=false

  for arg in "$@"; do
    case "$arg" in
      --incremental) incremental=true ;;
      --*)           warn "Unknown flag: $arg" ;;
      *)             app_arg="$arg" ;;
    esac
  done

  # Resolve backup root from config (falls back to /backup)
  local backup_root
  backup_root="$(config_get 'paths.backup' 2>/dev/null || echo "/backup")"
  [[ "$backup_root" == "null" || -z "$backup_root" ]] && backup_root="/backup"
  BACKUP_LOG="${backup_root}/backup.log"
  mkdir -p "$backup_root"

  _backup_acquire_lock
  trap '_backup_release_lock' EXIT INT TERM

  if [[ -n "$app_arg" ]]; then
    # Single app
    _backup_one_app "$app_arg" "$incremental"
    local rc=$?
    _backup_release_lock
    trap - EXIT INT TERM
    return $rc
  fi

  # All apps: find every container with a homekase.service label
  local all_containers
  all_containers="$(docker ps -a \
    --filter "label=com.homekase.service" \
    --format '{{.Names}}' 2>/dev/null || true)"

  if [[ -z "$all_containers" ]]; then
    info "Nothing to backup — no homekase services found."
    _backup_log "INFO no services found — nothing to backup"
    _backup_release_lock
    trap - EXIT INT TERM
    return 0
  fi

  local cname errors=0
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue
    local svc
    svc="$(_backup_get_label "$cname" "com.homekase.service")"
    [[ -z "$svc" ]] && continue
    _backup_one_app "$svc" "$incremental" || (( errors++ )) || true
  done <<< "$all_containers"

  if (( errors > 0 )); then
    warn "$errors backup(s) failed. Check $BACKUP_LOG for details."
  fi

  _backup_release_lock
  trap - EXIT INT TERM
  return 0
}
```

### Step 4: Run — expect pass

- [ ] Run the backup tests:

```bash
bats tests/test_backup.bats
```

Expected:
```
 ✓ cmd_backup unknown app exits 1 with error message
 ✓ cmd_backup with no apps exits 0 with nothing-to-backup message
 ✓ cmd_backup testapp creates destination directory
 ✓ cmd_backup testapp snapshot creates data.tar.gz
 ✓ cmd_backup --incremental testapp calls rsync not tar
 ✓ cmd_backup testapp writes to backup.log
6 tests, 0 failures
```

### Step 5: Run full test suite

- [ ] Confirm all existing tests still pass after adding the new test files:

```bash
make test
```

Expected:
```
:: Bats unit tests...
 ✓ [all test_common.bats tests]
 ✓ [all test_config.bats tests]
 ✓ [all test_dispatch.bats tests]
 ✓ [all test_status.bats tests]
 ✓ [all test_backup.bats tests]
N tests, 0 failures
```

### Step 6: Manual smoke test

- [ ] On the server, test with a real installed service (e.g. vikunja):

```bash
sudo homekase backup vikunja
```

Expected:
```
ℹ  Backing up vikunja → /backup/vikunja/20260612-143022
✓  data.tar.gz written
✓  Backed up vikunja to /backup/vikunja/20260612-143022
```

- [ ] Verify the backup directory and log:

```bash
ls /backup/vikunja/
cat /backup/backup.log
```

Expected: one timestamped directory; log shows `OK  vikunja  snapshot  /backup/vikunja/20260612-143022`.

- [ ] Test incremental backup (run once to create a first snapshot, then run again):

```bash
sudo homekase backup vikunja
sudo homekase backup vikunja --incremental
```

Expected: second run shows `Using previous snapshot for hardlinks` and creates a `data/` tree via rsync.

- [ ] Test all-services backup (cron-safe):

```bash
sudo homekase backup
```

Expected: iterates all containers with `com.homekase.service` label. Exits 0 even if no services are present.

- [ ] Verify lock prevents concurrent runs:

```bash
# In terminal 1 (simulate slow backup with a sleep-padded tar):
sudo homekase backup &
# In terminal 2 immediately:
sudo homekase backup
```

Expected: terminal 2 prints `Another homekase backup is already running (PID ...). Exiting.` and exits 1.

### Step 7: ShellCheck

- [ ] Run ShellCheck:

```bash
shellcheck -x lib/backup.sh
```

Expected: zero errors. If SC2086 is flagged for `$link_dest_arg` (intentionally unquoted for optional argument), the inline `# shellcheck disable=SC2086` already suppresses it.

### Step 8: Commit

- [ ] Stage and commit:

```bash
git add lib/backup.sh tests/test_backup.bats
git commit -m "feat: implement homekase backup with snapshot, incremental rsync, db dump, and cron lock"
```

---

## Self-Review

### Spec coverage

| Requirement | Status | Task/Step |
|-------------|--------|-----------|
| `cmd_status` pretty-prints System (hostname, uptime, load, RAM) | covered | Task 1 Step 3 |
| `cmd_status` pretty-prints Disk for /data /storage /backup | covered | Task 1 Step 3 |
| `cmd_status` pretty-prints Services with ● / ○ symbols | covered | Task 1 Step 3 |
| `cmd_status --json` emits valid JSON with system/disk/services keys | covered | Task 1 Step 3 |
| JSON services include `url` with Tailscale hostname + port when `tailscale=true` | covered | `_status_collect_services` |
| `cmd_backup <app>` exits 1 when app not found | covered | `_backup_one_app` |
| `cmd_backup` (no app) exits 0 when no services | covered | Task 2 Step 3 |
| `cmd_backup <app>` creates `/backup/<app>/<DATESTAMP>/` | covered | `_backup_snapshot` |
| Snapshot: `data.tar.gz` from `backup.data` label | covered | `_backup_snapshot` |
| Snapshot: optional `storage.tar.gz` from `backup.storage` label | covered | `_backup_snapshot` |
| Snapshot: `pg_dump` for `backup.db-type=postgres` | covered | `_backup_dump_db` |
| Snapshot: `mysqldump` for `backup.db-type=mysql` | covered | `_backup_dump_db` |
| Snapshot: `mongodump` + `docker cp` for `backup.db-type=mongodb` | covered | `_backup_dump_db` |
| Incremental: `rsync --link-dest` instead of tar | covered | `_backup_incremental` |
| Incremental: DB dump still fresh SQL (not delta) | covered | `_backup_incremental` |
| Lockfile at `/tmp/homekase-backup.lock` prevents overlap | covered | `_backup_acquire_lock` |
| Logs to `/backup/backup.log` | covered | `_backup_log` |
| `backup.type=none` skipped without error | covered | `_backup_one_app` |
| Tests mock docker via PATH override | covered | Task 1 Step 1, Task 2 Step 1 |
| `make test` passes after both tasks | covered | Task 2 Step 5 |

### Not in this plan (by design)

- Per-service retention / pruning of old backups — future enhancement
- `homekase restore` — future plan
- Encrypted backups — not in spec
- Remote backup targets (S3, SFTP) — not in spec

### Placeholder scan

None. Every step contains real bash code, expected output, or an explicit rationale for why it is absent.

### Dependency notes

- `jq` must be installed on the server for `cmd_status --json` and for JSON assembly in `cmd_status`. Add `jq` to the `homekase init` pre-selected tool list (Plan 3) or verify it is already installed by `homekase init`. The `make setup-dev` target should also check for `jq`.
- `rsync` must be installed for `--incremental`. This is a standard Debian/Ubuntu package (`apt install rsync`). Add a `is_installed rsync || error ...` guard inside `_backup_incremental` if desired.
- `free -m`, `/proc/loadavg`, `/proc/uptime`, and `df` are all standard Linux utilities present on any Debian/Ubuntu server — no install check needed.
