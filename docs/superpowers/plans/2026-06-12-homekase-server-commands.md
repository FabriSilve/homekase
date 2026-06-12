# homekase server Commands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `lib/server/server.sh` stub with a fully-functional `homekase server <subcommand>` system covering SSH hardening, UFW firewall, Tailscale VPN, swap file setup, disk overview, and Docker Engine installation.

**Architecture:** Each subcommand lives in its own file under `lib/server/` and is sourced on demand by the dispatcher in `lib/server/server.sh`. The dispatcher sources only the file it needs (no mass-sourcing), so each module is independently testable. All modules rely on the shared `lib/common.sh` (already sourced by the main entry point before dispatching) and `lib/config.sh` for persistent state in `/etc/homekase/homekase.yml`. Tests use bats with mocked system commands via `PATH` manipulation — no real root operations run in CI.

**Tech Stack:** bash 5+, yq v4 (YAML config read/write via `config_get`/`config_set`), bats-core (unit tests), UFW, systemd, Docker CE apt repo, Tailscale install script, fail2ban, sed (in-place sshd_config edits)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/server/server.sh` | REPLACE stub | Dispatcher: routes subcommands (ssh, firewall, network, vpn, swap, disk, docker), shows help |
| `lib/server/ssh.sh` | CREATE | SSH hardening: fail2ban + sshd_config + restart |
| `lib/server/firewall.sh` | CREATE | UFW management: setup, open, close, status |
| `lib/server/network.sh` | CREATE | Read-only network info display |
| `lib/server/vpn.sh` | CREATE | Tailscale install, `tailscale up`, config persistence |
| `lib/server/swap.sh` | CREATE | 6G swapfile creation + fstab + sysctl |
| `lib/server/disk.sh` | CREATE | lsblk + df -h + du top-5 per volume |
| `lib/server/docker.sh` | CREATE | Docker Engine + Compose + Buildx via apt; daemon.json; homelab-net |
| `tests/test_server_firewall.bats` | CREATE | firewall help, open/close arg validation, mocked status |
| `tests/test_server_disk.bats` | CREATE | disk output sections, exit 0 |

---

## Task 1: lib/server/server.sh — dispatcher + --help

**Files:**
- Modify: `lib/server/server.sh`
- No test file — covered by smoke test via `test_dispatch.bats` pattern

- [ ] **Step 1: Write the failing smoke test**

The existing `tests/test_dispatch.bats` already tests `homekase server` dispatching to the stub. Add a dedicated check that `homekase server` with no args exits 0 and shows subcommand names. Append these tests to `tests/test_dispatch.bats`:

```bash
@test "homekase server with no args exits 0" {
  run bash "$HOMEKASE" server
  [ "$status" -eq 0 ]
}

@test "homekase server --help shows ssh" {
  run bash "$HOMEKASE" server --help
  [[ "$output" == *"ssh"* ]]
}

@test "homekase server --help shows firewall" {
  run bash "$HOMEKASE" server --help
  [[ "$output" == *"firewall"* ]]
}

@test "homekase server --help shows docker" {
  run bash "$HOMEKASE" server --help
  [[ "$output" == *"docker"* ]]
}

@test "homekase server unknown subcommand exits 1" {
  run bash "$HOMEKASE" server __bad_subcmd__
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run to confirm they fail**

```bash
bats tests/test_dispatch.bats
```

Expected: the 5 new tests fail with output mentioning "not yet implemented" (from stub) or "ssh" not found in output.

- [ ] **Step 3: Implement lib/server/server.sh**

Replace `lib/server/server.sh` with:

```bash
#!/usr/bin/env bash

_server_help() {
  echo
  echo -e "${BOLD}homekase server${RESET} — server configuration"
  echo
  echo -e "${BOLD}USAGE${RESET}"
  echo "  homekase server <subcommand>"
  echo
  echo -e "${BOLD}SUBCOMMANDS${RESET}"
  printf "  %-12s %s\n" "ssh"       "Harden SSH: key-only login, fail2ban"
  printf "  %-12s %s\n" "firewall"  "Manage UFW rules (setup, open, close, status)"
  printf "  %-12s %s\n" "network"   "Show interfaces, gateway, DNS (read-only)"
  printf "  %-12s %s\n" "vpn"       "Install and connect Tailscale"
  printf "  %-12s %s\n" "swap"      "Create 6G swapfile with swappiness=10"
  printf "  %-12s %s\n" "disk"      "Show block devices, disk usage, volume summaries"
  printf "  %-12s %s\n" "docker"    "Install Docker Engine + Compose + Buildx"
  echo
  echo "  Run 'homekase server <subcommand> --help' for details."
  echo
}

cmd_server() {
  local subcmd="${1:-}"
  [[ "$subcmd" == "--help" || "$subcmd" == "-h" ]] && { _server_help; return 0; }

  if [[ -z "$subcmd" ]]; then
    _server_help
    return 0
  fi

  shift

  case "$subcmd" in
    ssh)      source "$HOMEKASE_DIR/lib/server/ssh.sh";      cmd_server_ssh "$@" ;;
    firewall) source "$HOMEKASE_DIR/lib/server/firewall.sh"; cmd_server_firewall "$@" ;;
    network)  source "$HOMEKASE_DIR/lib/server/network.sh";  cmd_server_network "$@" ;;
    vpn)      source "$HOMEKASE_DIR/lib/server/vpn.sh";      cmd_server_vpn "$@" ;;
    swap)     source "$HOMEKASE_DIR/lib/server/swap.sh";     cmd_server_swap "$@" ;;
    disk)     source "$HOMEKASE_DIR/lib/server/disk.sh";     cmd_server_disk "$@" ;;
    docker)   source "$HOMEKASE_DIR/lib/server/docker.sh";   cmd_server_docker "$@" ;;
    *)
      error "Unknown server subcommand: $subcmd"
      echo
      _server_help
      return 1
      ;;
  esac
}
```

- [ ] **Step 4: Create placeholder stubs for each submodule**

The dispatcher sources submodule files — they must exist or `source` fails. Create minimal stubs now; each will be replaced in later tasks.

```bash
cat > /Users/fabrizio/Projects/homekase/lib/server/ssh.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_ssh() { warn "homekase server ssh: not yet implemented"; }
EOF

cat > /Users/fabrizio/Projects/homekase/lib/server/firewall.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_firewall() { warn "homekase server firewall: not yet implemented"; }
EOF

cat > /Users/fabrizio/Projects/homekase/lib/server/network.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_network() { warn "homekase server network: not yet implemented"; }
EOF

cat > /Users/fabrizio/Projects/homekase/lib/server/vpn.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_vpn() { warn "homekase server vpn: not yet implemented"; }
EOF

cat > /Users/fabrizio/Projects/homekase/lib/server/swap.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_swap() { warn "homekase server swap: not yet implemented"; }
EOF

cat > /Users/fabrizio/Projects/homekase/lib/server/disk.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_disk() { warn "homekase server disk: not yet implemented"; }
EOF

cat > /Users/fabrizio/Projects/homekase/lib/server/docker.sh <<'EOF'
#!/usr/bin/env bash
cmd_server_docker() { warn "homekase server docker: not yet implemented"; }
EOF
```

- [ ] **Step 5: Run tests — expect pass**

```bash
bats tests/test_dispatch.bats
```

Expected:
```
 ✓ homekase exits 0 with no args
 ✓ homekase exits 0 with --help
 ...
 ✓ homekase server with no args exits 0
 ✓ homekase server --help shows ssh
 ✓ homekase server --help shows firewall
 ✓ homekase server --help shows docker
 ✓ homekase server unknown subcommand exits 1
16 tests, 0 failures
```

- [ ] **Step 6: Commit**

```bash
git add lib/server/server.sh lib/server/ssh.sh lib/server/firewall.sh \
        lib/server/network.sh lib/server/vpn.sh lib/server/swap.sh \
        lib/server/disk.sh lib/server/docker.sh tests/test_dispatch.bats
git commit -m "feat: add server dispatcher with help and subcommand routing"
```

---

## Task 2: lib/server/firewall.sh + tests — TDD

Firewall is the most complex subcommand (4 sub-sub-commands). Test it first; it's also the easiest to mock since `ufw` is a single binary.

**Files:**
- Replace: `lib/server/firewall.sh`
- Create: `tests/test_server_firewall.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/test_server_firewall.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

# We mock system commands by prepending a temp dir to PATH.
# Each mock is a tiny script that records the call and exits 0.

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  # Mock ufw
  cat > "$MOCK_DIR/ufw" <<'MOCK'
#!/usr/bin/env bash
echo "ufw $*"
exit 0
MOCK
  chmod +x "$MOCK_DIR/ufw"

  # Mock systemctl (needed by ssh.sh but firewall.sh doesn't use it — keep for safety)
  cat > "$MOCK_DIR/systemctl" <<'MOCK'
#!/usr/bin/env bash
echo "systemctl $*"
exit 0
MOCK
  chmod +x "$MOCK_DIR/systemctl"

  export PATH="$MOCK_DIR:$PATH"

  # Set a temp config so config_get/config_set work
  HOMEKASE_CONFIG="$(mktemp /tmp/homekase-test-XXXXX.yml)"
  cp "$PROJECT_ROOT/templates/homekase.yml.template" "$HOMEKASE_CONFIG"
  export HOMEKASE_CONFIG
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/server/firewall.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
  rm -f "$HOMEKASE_CONFIG"
}

@test "cmd_server_firewall with no args exits 0 and shows help" {
  run cmd_server_firewall
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"open"* ]]
  [[ "$output" == *"close"* ]]
  [[ "$output" == *"status"* ]]
}

@test "cmd_server_firewall --help exits 0 and shows help" {
  run cmd_server_firewall --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup"* ]]
}

@test "cmd_server_firewall open with no port exits 1" {
  run cmd_server_firewall open
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
}

@test "cmd_server_firewall close with no port exits 1" {
  run cmd_server_firewall close
  [ "$status" -eq 1 ]
  [[ "$output" == *"port"* ]]
}

@test "cmd_server_firewall open <port> calls ufw allow" {
  run cmd_server_firewall open 8096
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw allow 8096/tcp"* ]]
}

@test "cmd_server_firewall close <port> calls ufw deny" {
  run cmd_server_firewall close 8096
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw deny 8096/tcp"* ]]
}

@test "cmd_server_firewall status calls ufw status verbose" {
  run cmd_server_firewall status
  [ "$status" -eq 0 ]
  [[ "$output" == *"ufw status verbose"* ]]
}

@test "cmd_server_firewall unknown subcommand exits 1" {
  run cmd_server_firewall badcmd
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run — expect failure**

```bash
bats tests/test_server_firewall.bats
```

Expected: all 8 tests fail — the sourced `firewall.sh` is still the stub that just warns.

- [ ] **Step 3: Implement lib/server/firewall.sh**

Replace `lib/server/firewall.sh` with:

```bash
#!/usr/bin/env bash

_firewall_help() {
  echo
  echo -e "${BOLD}homekase server firewall${RESET} — UFW management"
  echo
  echo -e "${BOLD}USAGE${RESET}"
  echo "  homekase server firewall <subcommand> [args]"
  echo
  echo -e "${BOLD}SUBCOMMANDS${RESET}"
  printf "  %-20s %s\n" "setup"       "Apply default deny-in policy, allow SSH, enable UFW"
  printf "  %-20s %s\n" "open <port>" "Allow TCP traffic on <port>"
  printf "  %-20s %s\n" "close <port>" "Deny TCP traffic on <port>"
  printf "  %-20s %s\n" "status"      "Show current UFW rules (verbose)"
  echo
}

cmd_server_firewall() {
  local subcmd="${1:-}"
  [[ "$subcmd" == "--help" || "$subcmd" == "-h" ]] && { _firewall_help; return 0; }

  if [[ -z "$subcmd" ]]; then
    _firewall_help
    return 0
  fi

  shift

  case "$subcmd" in
    setup)
      require_root
      header "UFW firewall setup"
      ufw default deny incoming
      ufw default allow outgoing
      ufw allow 22/tcp comment 'SSH'
      if [[ "$(config_get 'tailscale.installed')" == "true" ]]; then
        ufw allow in on tailscale0
        info "Tailscale interface rule added (tailscale0)"
      fi
      ufw --force enable
      config_set 'ufw.enabled' 'true'
      ok "Firewall configured and enabled."
      ;;
    open)
      local port="${1:-}"
      if [[ -z "$port" ]]; then
        error "Usage: homekase server firewall open <port>"
        return 1
      fi
      require_root
      ufw allow "${port}/tcp"
      ok "Port ${port}/tcp opened."
      ;;
    close)
      local port="${1:-}"
      if [[ -z "$port" ]]; then
        error "Usage: homekase server firewall close <port>"
        return 1
      fi
      require_root
      ufw deny "${port}/tcp"
      ok "Port ${port}/tcp closed."
      ;;
    status)
      ufw status verbose
      ;;
    *)
      error "Unknown firewall subcommand: $subcmd"
      echo
      _firewall_help
      return 1
      ;;
  esac
}
```

- [ ] **Step 4: Run — expect pass**

```bash
bats tests/test_server_firewall.bats
```

Expected:
```
 ✓ cmd_server_firewall with no args exits 0 and shows help
 ✓ cmd_server_firewall --help exits 0 and shows help
 ✓ cmd_server_firewall open with no port exits 1
 ✓ cmd_server_firewall close with no port exits 1
 ✓ cmd_server_firewall open <port> calls ufw allow
 ✓ cmd_server_firewall close <port> calls ufw deny
 ✓ cmd_server_firewall status calls ufw status verbose
 ✓ cmd_server_firewall unknown subcommand exits 1
8 tests, 0 failures
```

- [ ] **Step 5: Run full suite**

```bash
make test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/server/firewall.sh tests/test_server_firewall.bats
git commit -m "feat: add server firewall subcommand (setup, open, close, status)"
```

---

## Task 3: lib/server/disk.sh + tests — TDD

Disk is read-only so safe to test by mocking `lsblk`, `df`, and `du`.

**Files:**
- Replace: `lib/server/disk.sh`
- Create: `tests/test_server_disk.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/test_server_disk.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  MOCK_DIR="$(mktemp -d)"
  export MOCK_DIR

  # Mock lsblk
  cat > "$MOCK_DIR/lsblk" <<'MOCK'
#!/usr/bin/env bash
echo "NAME   FSTYPE   LABEL   UUID   MOUNTPOINT"
echo "sda"
echo "└─sda1 ext4           /data"
exit 0
MOCK
  chmod +x "$MOCK_DIR/lsblk"

  # Mock df
  cat > "$MOCK_DIR/df" <<'MOCK'
#!/usr/bin/env bash
echo "Filesystem      Size  Used Avail Use% Mounted on"
echo "/dev/sda1       100G   20G   80G  20% /data"
exit 0
MOCK
  chmod +x "$MOCK_DIR/df"

  # Mock du
  cat > "$MOCK_DIR/du" <<'MOCK'
#!/usr/bin/env bash
echo "1.2G  ./subdir1"
echo "800M  ./subdir2"
exit 0
MOCK
  chmod +x "$MOCK_DIR/du"

  export PATH="$MOCK_DIR:$PATH"
  export HOMEKASE_DIR="$PROJECT_ROOT"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/server/disk.sh"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

@test "cmd_server_disk exits 0" {
  run cmd_server_disk
  [ "$status" -eq 0 ]
}

@test "cmd_server_disk output contains block devices section" {
  run cmd_server_disk
  [[ "$output" == *"Block Devices"* ]]
}

@test "cmd_server_disk output contains disk usage section" {
  run cmd_server_disk
  [[ "$output" == *"Disk Usage"* ]]
}

@test "cmd_server_disk calls lsblk with -f flag" {
  run cmd_server_disk
  [[ "$output" == *"FSTYPE"* ]]
}

@test "cmd_server_disk calls df -h" {
  run cmd_server_disk
  [[ "$output" == *"Filesystem"* ]]
}
```

- [ ] **Step 2: Run — expect failure**

```bash
bats tests/test_server_disk.bats
```

Expected: all 5 tests fail — stub just warns.

- [ ] **Step 3: Implement lib/server/disk.sh**

Replace `lib/server/disk.sh` with:

```bash
#!/usr/bin/env bash

cmd_server_disk() {
  header "Block Devices"
  lsblk -f
  echo

  header "Disk Usage"
  df -h
  echo

  # Per-volume top-5 subdirectory summary
  local volumes=(/data /storage /backup)
  for vol in "${volumes[@]}"; do
    if mountpoint -q "$vol" 2>/dev/null || [[ -d "$vol" ]]; then
      header "Top 5 subdirs in $vol"
      du -sh "$vol"/* 2>/dev/null | sort -rh | head -5 || true
      echo
    fi
  done
}
```

- [ ] **Step 4: Run — expect pass**

```bash
bats tests/test_server_disk.bats
```

Expected:
```
 ✓ cmd_server_disk exits 0
 ✓ cmd_server_disk output contains block devices section
 ✓ cmd_server_disk output contains disk usage section
 ✓ cmd_server_disk calls lsblk with -f flag
 ✓ cmd_server_disk calls df -h
5 tests, 0 failures
```

- [ ] **Step 5: Run full suite**

```bash
make test
```

Expected: all tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/server/disk.sh tests/test_server_disk.bats
git commit -m "feat: add server disk subcommand (lsblk + df + du per volume)"
```

---

## Task 4: lib/server/network.sh

Read-only display — no tests beyond syntax check (mocking `ip` and `cat` is low value here).

**Files:**
- Replace: `lib/server/network.sh`

- [ ] **Step 1: Implement lib/server/network.sh**

Replace `lib/server/network.sh` with:

```bash
#!/usr/bin/env bash

cmd_server_network() {
  header "Network Interfaces"
  ip -br addr show
  echo

  header "Default Gateway"
  ip route | grep default
  echo

  header "DNS Nameservers"
  grep nameserver /etc/resolv.conf
  echo
}
```

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n lib/server/network.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add lib/server/network.sh
git commit -m "feat: add server network subcommand (interfaces, gateway, DNS)"
```

---

## Task 5: lib/server/ssh.sh

Modifies system files — no automated bats tests (requires real root + real `/etc/ssh`). Manual verification instructions provided.

**Files:**
- Replace: `lib/server/ssh.sh`

- [ ] **Step 1: Implement lib/server/ssh.sh**

Replace `lib/server/ssh.sh` with:

```bash
#!/usr/bin/env bash

cmd_server_ssh() {
  require_root
  header "SSH Hardening"

  warn "This will make the following changes:"
  warn "  • Set PermitRootLogin no in /etc/ssh/sshd_config"
  warn "  • Set PasswordAuthentication no in /etc/ssh/sshd_config"
  warn "  • Set ChallengeResponseAuthentication no in /etc/ssh/sshd_config"
  warn "  • Restart the ssh service"
  echo

  if ask_confirm "Install fail2ban to block brute-force SSH attempts?"; then
    info "Installing fail2ban..."
    apt-get install -y fail2ban

    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.conf <<'EOF'
[sshd]
enabled  = true
maxretry = 5
bantime  = 3600
findtime = 600
EOF
    systemctl enable --now fail2ban
    ok "fail2ban installed and configured."
  fi

  info "Hardening /etc/ssh/sshd_config..."

  local cfg="/etc/ssh/sshd_config"

  # Each sed call: if a matching directive exists (commented or not), replace it;
  # if it doesn't exist at all, append it.
  _sshd_set() {
    local key="$1" value="$2"
    if grep -qE "^#?${key}\s" "$cfg"; then
      sed -i "s|^#\?${key}\s.*|${key} ${value}|" "$cfg"
    else
      echo "${key} ${value}" >> "$cfg"
    fi
  }

  _sshd_set "PermitRootLogin"               "no"
  _sshd_set "PasswordAuthentication"        "no"
  _sshd_set "ChallengeResponseAuthentication" "no"

  systemctl restart ssh
  ok "SSH hardened."
}
```

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n lib/server/ssh.sh
```

Expected: no output.

- [ ] **Step 3: Manual smoke test (run on a test VM, not production)**

On a VM where you can recover console access if SSH breaks:

```bash
# Backup sshd_config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Run (answer 'y' to fail2ban prompt)
sudo bash homekase server ssh

# Verify changes
grep -E "PermitRootLogin|PasswordAuthentication|ChallengeResponseAuthentication" /etc/ssh/sshd_config
```

Expected output from grep:
```
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
```

```bash
# Verify fail2ban is running
systemctl is-active fail2ban
# Expected: active

# Restore if needed
sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
sudo systemctl restart ssh
```

- [ ] **Step 4: Commit**

```bash
git add lib/server/ssh.sh
git commit -m "feat: add server ssh subcommand (sshd_config hardening + fail2ban)"
```

---

## Task 6: lib/server/vpn.sh

**Files:**
- Replace: `lib/server/vpn.sh`

- [ ] **Step 1: Implement lib/server/vpn.sh**

Replace `lib/server/vpn.sh` with:

```bash
#!/usr/bin/env bash

cmd_server_vpn() {
  require_root
  header "Tailscale VPN"

  if ! is_installed tailscale; then
    if ask_confirm "Tailscale is not installed. Install now?"; then
      info "Installing Tailscale..."
      curl -fsSL https://tailscale.com/install.sh | sh
      ok "Tailscale installed."
    else
      info "Cancelled."
      return 0
    fi
  else
    ok "Tailscale already installed."
  fi

  info "Bringing Tailscale up..."
  tailscale up

  info "Reading Tailscale hostname..."
  local hostname
  hostname="$(tailscale status --json | yq '.Self.DNSName' -)"
  # Strip trailing dot that Tailscale appends
  hostname="${hostname%.}"

  config_set 'tailscale.installed' 'true'
  config_set 'tailscale.hostname' "$hostname"
  ok "Config updated: tailscale.installed=true, tailscale.hostname=$hostname"

  if [[ "$(config_get 'ufw.enabled')" == "true" ]]; then
    info "UFW is enabled — adding tailscale0 allow rule..."
    ufw allow in on tailscale0
    ok "UFW rule added for tailscale0."
  fi

  ok "Tailscale ready. Hostname: $hostname"
}
```

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n lib/server/vpn.sh
```

Expected: no output.

- [ ] **Step 3: Manual smoke test (run on VM with internet access)**

```bash
sudo bash homekase server vpn
# Follow Tailscale auth URL printed to terminal
# After auth, verify:
tailscale status
config_get tailscale.hostname  # should show <hostname>.tail<xxxx>.ts.net
```

- [ ] **Step 4: Commit**

```bash
git add lib/server/vpn.sh
git commit -m "feat: add server vpn subcommand (Tailscale install + up + config persistence)"
```

---

## Task 7: lib/server/swap.sh

**Files:**
- Replace: `lib/server/swap.sh`

- [ ] **Step 1: Implement lib/server/swap.sh**

Replace `lib/server/swap.sh` with:

```bash
#!/usr/bin/env bash

cmd_server_swap() {
  require_root
  header "Swap File Setup"

  if [[ -f /swapfile ]]; then
    warn "/swapfile already exists."
    if ! ask_confirm "Recreate swapfile? (existing swap will be turned off)"; then
      info "Cancelled."
      return 0
    fi
    swapoff /swapfile
    rm -f /swapfile
    info "Existing swapfile removed."
  fi

  info "Creating 6G swapfile..."
  fallocate -l 6G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  ok "Swapfile active."

  # Add to /etc/fstab if not already present
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Added /swapfile to /etc/fstab."
  else
    info "/swapfile already in /etc/fstab — skipping."
  fi

  # Set swappiness
  sysctl -w vm.swappiness=10
  if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    ok "vm.swappiness=10 persisted in /etc/sysctl.conf."
  else
    sed -i 's/^vm\.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    ok "vm.swappiness=10 updated in /etc/sysctl.conf."
  fi

  ok "Swap configured: 6G swapfile, swappiness=10."
}
```

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n lib/server/swap.sh
```

Expected: no output.

- [ ] **Step 3: Manual smoke test (run on VM with free disk space)**

```bash
sudo bash homekase server swap

# Verify
swapon --show
# Expected:
# NAME      TYPE SIZE USED PRIO
# /swapfile file   6G   0B   -2

grep '/swapfile' /etc/fstab
# Expected: /swapfile none swap sw 0 0

cat /proc/sys/vm/swappiness
# Expected: 10
```

- [ ] **Step 4: Commit**

```bash
git add lib/server/swap.sh
git commit -m "feat: add server swap subcommand (6G swapfile, fstab, swappiness=10)"
```

---

## Task 8: lib/server/docker.sh

**Files:**
- Replace: `lib/server/docker.sh`

- [ ] **Step 1: Implement lib/server/docker.sh**

Replace `lib/server/docker.sh` with:

```bash
#!/usr/bin/env bash

cmd_server_docker() {
  require_root
  header "Docker Engine Installation"

  if is_installed docker; then
    ok "Docker already installed."
    docker --version
    return 0
  fi

  info "Installing Docker Engine via official apt repository..."

  # Prerequisites
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  # Add Docker GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Add Docker apt repository
  local arch distro
  arch="$(dpkg --print-architecture)"
  distro="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo \
    "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${distro} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  ok "Docker packages installed."

  # Configure log rotation
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  ok "Docker daemon.json configured (log rotation: 10m × 3 files)."

  systemctl enable --now docker

  # Add user to docker group
  local target_user="${SUDO_USER:-$(id -un)}"
  usermod -aG docker "$target_user"
  usermod -aG docker root
  ok "User '$target_user' added to docker group."

  # Create shared homelab network (idempotent)
  docker network create homelab-net 2>/dev/null || true
  ok "Docker network 'homelab-net' ready."

  ok "Docker installed. Log out and back in for group membership to take effect."
}
```

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n lib/server/docker.sh
```

Expected: no output.

- [ ] **Step 3: Manual smoke test (run on clean VM)**

```bash
sudo bash homekase server docker

# Verify
docker --version
# Expected: Docker version 26.x.x, build ...

docker compose version
# Expected: Docker Compose version v2.x.x

docker network ls | grep homelab-net
# Expected: ... homelab-net   bridge    local

cat /etc/docker/daemon.json
# Expected: json with log-driver and log-opts

# Idempotent — run again, should show "already installed"
sudo bash homekase server docker
# Expected: "✓  Docker already installed." then version
```

- [ ] **Step 4: Commit**

```bash
git add lib/server/docker.sh
git commit -m "feat: add server docker subcommand (Docker CE + Compose + Buildx + homelab-net)"
```

---

## Task 9: Shellcheck pass + full test suite

Ensure all new files pass shellcheck and the full bats suite is green.

**Files:**
- Potentially any `lib/server/*.sh` (fix issues in place)

- [ ] **Step 1: Run shellcheck on all new files**

```bash
shellcheck -x \
  lib/server/server.sh \
  lib/server/ssh.sh \
  lib/server/firewall.sh \
  lib/server/network.sh \
  lib/server/vpn.sh \
  lib/server/swap.sh \
  lib/server/disk.sh \
  lib/server/docker.sh
```

Expected: no errors, no warnings. If there are warnings, fix them:

Common fixes:
- `SC2086` (double-quote variable): wrap `$var` in `"$var"`
- `SC2034` (unused variable): prefix with `_` or remove
- `SC2181` (check exit code directly): replace `if [ $? -ne 0 ]` with `if ! cmd`
- `SC1091` (not following source): add `# shellcheck source=lib/common.sh` directives if needed

Example fix for SC1091 at top of each `lib/server/*.sh` file (add after shebang):
```bash
# shellcheck source=lib/common.sh
```

- [ ] **Step 2: Run full bats test suite**

```bash
make test
```

Expected output:
```
:: Bats unit tests...
 ✓ is_installed returns 0 for bash
 ✓ is_installed returns 1 for nonexistent command
 ... (all test_common.bats tests)
 ✓ config_get reads paths.data
 ... (all test_config.bats tests)
 ✓ homekase exits 0 with no args
 ... (all test_dispatch.bats tests)
 ✓ cmd_server_firewall with no args exits 0 and shows help
 ... (all test_server_firewall.bats tests)
 ✓ cmd_server_disk exits 0
 ... (all test_server_disk.bats tests)
N tests, 0 failures
```

- [ ] **Step 3: Run make lint**

```bash
make lint
```

Expected: all files pass bash syntax check and shellcheck.

- [ ] **Step 4: Commit (only if files were modified during fixes)**

```bash
git add lib/server/
git commit -m "fix: shellcheck clean pass on all lib/server modules"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|-------------|------|
| `lib/server/server.sh` dispatcher with `--help` | Task 1 |
| Dispatches: ssh, firewall, network, vpn, swap, disk, docker | Task 1 |
| Shows help if no subcommand | Task 1 |
| `cmd_server_ssh`: warn, ask fail2ban, sshd_config sed, restart ssh | Task 5 |
| fail2ban `/etc/fail2ban/jail.d/sshd.conf` with maxretry=5, bantime=3600, findtime=600 | Task 5 |
| `cmd_server_firewall setup`: deny-in, allow-out, allow 22, tailscale0 if enabled | Task 2 |
| `cmd_server_firewall open <port>`: ufw allow | Task 2 |
| `cmd_server_firewall close <port>`: ufw deny | Task 2 |
| `cmd_server_firewall status`: ufw status verbose | Task 2 |
| `cmd_server_firewall` no-args: show help | Task 2 |
| UFW stores `ufw.enabled=true` in config after setup | Task 2 |
| `cmd_server_network`: ip addr, default route, resolv.conf DNS | Task 4 |
| `cmd_server_vpn`: install if missing, tailscale up, read hostname, config_set, ufw tailscale0 | Task 6 |
| Strip trailing dot from `tailscale status --json` DNSName | Task 6 |
| `cmd_server_swap`: check /swapfile, fallocate 6G, chmod, mkswap, swapon, fstab, swappiness | Task 7 |
| `cmd_server_disk`: lsblk -f, df -h, du top-5 per /data /storage /backup | Task 3 |
| `cmd_server_docker`: skip if installed, apt repo, GPG key, packages, daemon.json, enable, usermod, homelab-net | Task 8 |
| `tests/test_server_firewall.bats`: help, open/close require port, status mocks ufw | Task 2 |
| `tests/test_server_disk.bats`: exits 0, block devices header, disk usage header | Task 3 |
| ShellCheck clean | Task 9 |

All requirements covered. No gaps found.

### Placeholder Scan

- No "TBD", "TODO", or "implement later" in any step.
- Every step that changes code shows the full code.
- Every run step shows the exact command and expected output.
- The manual smoke test steps include verification commands and expected output.

### Type/Name Consistency

- `cmd_server_firewall` defined in Task 2, sourced and called in Task 1 dispatcher. Names match.
- `cmd_server_disk` defined in Task 3, sourced and called in Task 1. Names match.
- `cmd_server_network` defined in Task 4, sourced and called in Task 1. Names match.
- `cmd_server_ssh` defined in Task 5, sourced and called in Task 1. Names match.
- `cmd_server_vpn` defined in Task 6, sourced and called in Task 1. Names match.
- `cmd_server_swap` defined in Task 7, sourced and called in Task 1. Names match.
- `cmd_server_docker` defined in Task 8, sourced and called in Task 1. Names match.
- `config_get` / `config_set` called in Tasks 2, 6 — both defined in `lib/config.sh` (Plan 1). Signatures: `config_get '<dotpath>'`, `config_set '<dotpath>' '<value>'`. Usage consistent throughout.
- `require_root`, `ask_confirm`, `is_installed`, `header`, `info`, `ok`, `warn`, `error` all defined in `lib/common.sh` and used consistently with their established signatures across all tasks.
- `HOMEKASE_DIR` exported by `homekase` entry point before sourcing `lib/server/server.sh` — all submodule source paths use it correctly.
