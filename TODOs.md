# TODOs

## Security

### Secrets Management
- [x] **Secrets stored in docker-compose.yml files**: Moved to `.env` files per service (immich, github-runner, qbittorrent).
  - `homekase.fish` — RUNNER_TOKEN still appended to compose (fish function, separate fix needed)
- [x] **Immich DB password fallback**: Now auto-generates with `openssl rand -base64 24` if user skips prompt.
- [x] **DB password printed to stdout in `homekase create`**: Now points user to `.env` file instead.

### Network / Access
- [ ] **Traefik dashboard exposed without authentication**: `dashboard.home` has no basic auth or IP whitelist. Anyone on LAN can see all routes.
- [ ] **No TLS anywhere**: all services on plain HTTP. Add Let's Encrypt (for public) or self-signed cert option (for LAN).
- [ ] **AdGuard initial setup on port 3000 with no auth**: first-access wizard is open to anyone on the network. Race condition — someone else could configure it first.
- [ ] **qBittorrent default credentials `admin/adminadmin`**: warn message is not enough. Consider auto-generating password and writing to `.env`.
- [ ] **Port 53 open to all interfaces**: AdGuard DNS listens on `53:53/udp` — exposed to entire LAN. Fine for intended use, but should be documented as intentional.

### Container Security
- [ ] **Docker socket mounted in GitHub runner**: `github-runner.sh` and `homekase.fish` mount `/var/run/docker.sock` — grants container full root access to host. Document the risk; consider using Docker-in-Docker or Sysbox instead.
- [ ] **GitHub runner image unpinned**: `myoung34/github-runner:latest` — supply chain risk. Pin to specific digest or version tag.
- [ ] **All service images use `latest`**: AdGuard, Jellyfin, qBittorrent, Syncthing, Beszel — all unpinned. Pin versions for reproducibility.

### SSH / System
- [ ] **No SSH hardening**: no fail2ban, no key-only auth enforcement, no `PermitRootLogin no` check. Consider adding as optional step.
- [ ] **`curl | sudo bash` pattern**: inherent risk (standard in the ecosystem, but worth documenting). The script does clone to temp dir first which is good.

## Idempotency

Things that break or behave badly on re-run (`homekase update` or re-running `setup.sh`).

### Broken on Re-run (Data Corruption / Duplication) — ALL FIXED
- [x] **`config.fish` appended every run**: Now writes to `conf.d/homekase.fish` with overwrite (`>`), not append.
- [x] **`urls.txt` appended every deploy**: Now uses `append_url` helper with `grep -qF` dedup check.
- [x] **`/etc/fstab` appended without dedup check**: Now checks `grep -qF` before appending + backs up fstab.
- [x] **`ufw --force reset` on every run**: Now checks if UFW already active with correct rules, skips if so. Also prompts before applying.

### Not Guarded (Re-downloads / Overwrites) — ALL FIXED
- [x] **`install_shell_tools` re-downloads everything**: Now guarded with `is_installed` checks for lazygit, yazi, gh.
- [x] **`install_neovim` re-downloads nvim binary every run**: Now guarded with `is_installed nvim`.
- [ ] **`install_base_packages` re-runs apt install**: harmless (apt skips installed packages) but slow. Low priority.

### Correctly Guarded (No Action Needed)
- `install_docker` — guarded with `is_installed docker`
- `install_starship` — guarded with `is_installed starship`
- `set_fish_default` — guarded with `/etc/passwd` check + prompt before changing
- `setup_lvm_and_mount` — guarded with `mountpoint -q`
- All `deploy_*` functions — guarded with `docker compose ls | grep`
- LazyVim clone — guarded with `dir_exists`

## Disk Operations

- [x] **No blank-disk check before LVM**: Now shows existing partitions with `lsblk -f` and requires confirmation.
- [x] **No fstab backup**: Now backs up to `/etc/fstab.bak` before modifying.
- [x] **80% LVM allocation hardcoded**: Now explained to user during setup.
- [x] **No error handling if pvcreate fails**: Now catches failure and suggests `wipefs -a` as manual fix.

## Package Management

- [ ] **Migrate lazygit to apt/repo install**: currently downloads binary via curl + tar. Should add PPA or use apt repo pattern for consistency with gum/gh.
- [ ] **Migrate yazi to apt/repo install**: currently downloads binary via curl + zip. Same pattern as lazygit.

## Robustness

- [x] **No app name validation in `homekase create`**: Now validates `[a-z0-9-]` only.
- [x] **`get_home()` uses `eval echo ~user`**: Now uses `getent passwd` which is safer.
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

### High Priority — ALL DONE
- [x] **`configure_firewall`**: Now uses `section` to explain + asks confirmation before applying.
- [x] **`set_fish_default`**: Now explains fish and asks "Set fish as your default shell?" before changing.
- [x] **`deploy_adguard`**: Now explains what AdGuard does and asks before deploying.

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

Pattern: use `prompt_choose` helper (now available in common.sh / common_wizard.sh).

### Low Priority (Nice to Have)

- [ ] **`run_system_update`**: runs apt update + upgrade silently. Consider brief explanation.
- [ ] **`install_docker`**: core infrastructure, well-guarded. Consider brief explanation.

### General Wizard Improvements

- [ ] **Add a welcome/overview step**: before anything runs, show a summary of what the setup will do.
- [ ] **Add step numbering**: e.g. "Step 3/8: Shell Tools" so user knows progress.
- [ ] **Group optional tools into a selection menu**: similar to `service_menu` but for dev tools.

### Already Good (Wizard Pattern Followed)

- `run_disk_setup` — shows table, prompts selection, allows skip. Well done.
- `service_menu` — description + yes/no per service. Clean pattern.
- `deploy_immich` — prompts for DB password (now auto-generates if empty).
- `deploy_qbittorrent` — asks about VPN, prompts for provider/keys.
- `deploy_github_runner` — prompts for org and token.
