# TODOs

## Security

### Secrets Management
- [ ] **Secrets stored in docker-compose.yml files**: DB passwords, runner tokens, WireGuard private keys are all written directly in compose YAML. Should use `.env` files per service. Affected:
  - `immich.sh` — DB_PASSWORD in compose (4 places)
  - `github-runner.sh` — RUNNER_TOKEN in compose
  - `qbittorrent.sh` — WIREGUARD_PRIVATE_KEY in compose
  - `homekase.fish` — RUNNER_TOKEN appended to compose
- [ ] **Immich DB password fallback**: silently defaults to `change_this_password` if user skips prompt. Should require input or auto-generate with `openssl rand -base64 24` (like `homekase.fish` already does for app scaffolding).
- [ ] **DB password printed to stdout in `homekase create`**: `homekase.fish:127` prints password to terminal. Consider writing to `.env` only and telling user where to find it.

### Network / Access
- [ ] **Traefik dashboard exposed without authentication**: `dashboard.home` has no basic auth or IP whitelist. Anyone on LAN can see all routes.
- [ ] **No TLS anywhere**: all services on plain HTTP. Add Let's Encrypt (for public) or self-signed cert option (for LAN).
- [ ] **AdGuard initial setup on port 3000 with no auth**: first-access wizard is open to anyone on the network. Race condition — someone else could configure it first.
- [ ] **qBittorrent default credentials `admin/adminadmin`**: warn message is not enough. Consider auto-generating password and writing to `.env`.
- [ ] **Port 53 open to all interfaces**: AdGuard DNS listens on `53:53/udp` — exposed to entire LAN. Fine for intended use, but should be documented as intentional.

### Container Security
- [ ] **Docker socket mounted in GitHub runner**: `github-runner.sh:26` and `homekase.fish:111` mount `/var/run/docker.sock` — grants container full root access to host. Document the risk; consider using Docker-in-Docker or Sysbox instead.
- [ ] **GitHub runner image unpinned**: `myoung34/github-runner:latest` — supply chain risk. Pin to specific digest or version tag.
- [ ] **All service images use `latest`**: AdGuard, Jellyfin, qBittorrent, Syncthing, Beszel — all unpinned. Pin versions for reproducibility.

### SSH / System
- [ ] **No SSH hardening**: no fail2ban, no key-only auth enforcement, no `PermitRootLogin no` check. Consider adding as optional step.
- [ ] **`curl | sudo bash` pattern**: inherent risk (standard in the ecosystem, but worth documenting). The script does clone to temp dir first which is good.

## Idempotency

Things that break or behave badly on re-run (`homekase update` or re-running `setup.sh`).

### Broken on Re-run (Data Corruption / Duplication)
- [ ] **`config.fish` appended every run** (`users.sh:24`): `cat >>` adds the config block again each time. Fish will source duplicated aliases/env vars. Fix: check if marker comment exists before appending, or write to a separate `homekase.fish` conf.d file.
- [ ] **`urls.txt` appended every deploy**: every `deploy_*` function does `cat >> urls.txt` without checking if entry already exists. Re-running setup duplicates all URL entries. Fix: check with `grep -q` before appending (like `homekase.fish:132` already does correctly).
- [ ] **`/etc/fstab` appended without dedup check** (`disks.sh:90`): `echo >> /etc/fstab` adds mount entry every run. Multiple identical fstab lines. Fix: `grep -q "$mount_point" /etc/fstab || echo >> /etc/fstab`.
- [ ] **`ufw --force reset` on every run** (`system.sh:27`): wipes ALL existing firewall rules including any custom rules user added after initial setup. Fix: check if rules already match expected state, or skip if UFW is already active with correct rules.

### Not Guarded (Re-downloads / Overwrites)
- [ ] **`install_shell_tools` re-downloads everything**: lazygit, yazi, gh keyring — all re-fetched and overwritten every run. No version check. Fix: check `lazygit --version`, `yazi --version` before downloading.
- [ ] **`install_neovim` re-downloads nvim binary every run**: only LazyVim clone is guarded (`dir_exists`). Nvim itself gets re-downloaded and extracted. Fix: check `nvim --version` or existence of `/opt/nvim-linux-x86_64`.
- [ ] **`install_base_packages` re-runs apt install**: harmless (apt skips installed packages) but slow. Low priority.

### Correctly Guarded (No Action Needed)
- `install_docker` — guarded with `is_installed docker`
- `install_starship` — guarded with `is_installed starship`
- `set_fish_default` — guarded with `/etc/passwd` check (shell change only, but config.fish append is NOT guarded)
- `setup_lvm_and_mount` — guarded with `mountpoint -q`
- All `deploy_*` functions — guarded with `docker compose ls | grep`
- LazyVim clone — guarded with `dir_exists`

## Disk Operations

- [ ] **No blank-disk check before LVM**: `pvcreate`/`vgcreate` will destroy data without warning. Add confirmation showing existing partitions/filesystem with `lsblk -f` or `blkid`.
- [ ] **No fstab backup**: should `cp /etc/fstab /etc/fstab.bak` before modifying.
- [ ] **80% LVM allocation hardcoded**: sensible default but should be explained to user during disk selection.
- [ ] **No error handling if pvcreate fails**: e.g. if disk has existing partitions or LVM signature. Should catch and offer to wipe.

## Robustness

- [ ] **No app name validation in `homekase create`**: special chars, spaces, slashes will break sed substitution and Docker labels. Validate: `[a-z0-9-]` only.
- [ ] **`get_home()` uses `eval echo ~user`**: works but fragile — consider `getent passwd "$user" | cut -d: -f6`.
- [ ] **No pre-flight check for required commands**: lsblk, findmnt needed for disk setup but not checked upfront.

## Testing

- [ ] **Tests only mock deploy functions**: no real Docker stack validation.
- [ ] **Docker integration test only validates dry-run**: not actual deployment.
- [ ] **Custom `test_helper.bash`**: missing `assert_equal`. Consider switching to `bats-assert` library.

## Templates

- [ ] **`package.json` no version pinning**: dependencies use exact versions but no lock file strategy.
- [ ] **GitHub Actions deploy workflow hardcodes `localhost`**: fragile health check.

---

## UX / Wizard Flow

Steps that run silently but should follow the wizard pattern (explain what it is, what options mean, let user confirm before executing).

### High Priority

- [ ] **`configure_firewall`**: silently runs `ufw --force reset` and opens SSH, 80, 443, 53/UDP. Should:
  - Explain: "This configures the firewall to allow only SSH, HTTP, HTTPS, and DNS traffic. All other incoming connections will be blocked."
  - Show the ports that will be opened.
  - Ask for confirmation before applying (especially the `--force reset` which wipes existing rules).

- [ ] **`set_fish_default`**: changes the user's default shell with no prompt. Should:
  - Explain: "Fish is a modern shell with syntax highlighting and auto-suggestions. This will change your default shell from bash to fish."
  - Ask: "Set fish as your default shell? [Y/n]"
  - This is a significant UX change — user should consent.

- [ ] **`deploy_adguard`**: deploys a DNS server without asking. Should:
  - Explain: "AdGuard Home is a DNS server that blocks ads and enables *.home domain routing."
  - Ask: "Deploy AdGuard Home? [Y/n]"
  - Or move it into the service_menu alongside other optional services.

### Medium Priority — Tool Selection Menus

Each tool category should present a numbered selection menu. Only two options now, but designed for expansion later.

- [ ] **Terminal editor selection**:
  ```
  Which terminal editor do you want?
    1) LazyVim — Neovim with IDE features pre-configured
    2) Skip — I'll install my own editor
  ```
  Future options: nano, vim (vanilla), Helix, emacs, etc.

- [ ] **Git TUI selection**:
  ```
  Which git tool do you want?
    1) lazygit — Terminal UI for git commands
    2) Skip — I'll use git CLI or my own tool
  ```
  Future options: tig, gitui, etc.

- [ ] **Shell prompt selection**:
  ```
  Which shell prompt do you want?
    1) Starship — Fast prompt showing git status, language versions, etc.
    2) Skip — I'll configure my own prompt
  ```
  Future options: oh-my-fish themes, tide, pure, etc.

- [ ] **File manager selection**:
  ```
  Which terminal file manager do you want?
    1) yazi — Fast TUI file manager with preview
    2) Skip — I'll use ls/find or my own
  ```
  Future options: ranger, nnn, lf, etc.

- [ ] **Terminal multiplexer selection**:
  ```
  Which terminal multiplexer do you want?
    1) zellij — Modern terminal workspace with built-in layouts
    2) Skip — I'll use tmux or my own
  ```
  Future options: tmux, screen, etc.

Pattern: use a generic `tool_select "Category prompt" option1 desc1 option2 desc2 ...` helper in common.sh so adding new categories or options is trivial.

### Low Priority (Nice to Have)

- [ ] **`run_system_update`**: runs apt update + upgrade silently. Consider:
  - Brief explanation: "Updating system packages to latest versions."
  - No prompt needed — this is standard and expected.

- [ ] **`install_docker`**: core infrastructure, well-guarded. Consider:
  - Brief explanation: "Docker is required for all services. Installing Docker Engine + Compose."
  - No prompt needed — it's a prerequisite.

### General Wizard Improvements

- [ ] **Add a welcome/overview step**: before anything runs, show a summary of what the setup will do (system update, tools, disk setup, services) so user knows what to expect.
- [ ] **Add step numbering**: e.g. "Step 3/8: Shell Tools" so user knows progress.
- [ ] **Add a confirmation before destructive steps**: especially disk setup and firewall reset.
- [ ] **Group optional tools into a selection menu**: similar to `service_menu` but for dev tools (fish, nvim, starship, lazygit, etc.).

### Already Good (Wizard Pattern Followed)

- `run_disk_setup` — shows table, prompts selection, allows skip. Well done.
- `service_menu` — description + yes/no per service. Clean pattern.
- `deploy_immich` — prompts for DB password.
- `deploy_qbittorrent` — asks about VPN, prompts for provider/keys.
- `deploy_github_runner` — prompts for org and token.
