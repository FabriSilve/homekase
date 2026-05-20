# TODOs

## Security

### Secrets Management — ALL DONE
- [x] **Secrets stored in docker-compose.yml files**: Moved to `.env` files per service (immich, github-runner, qbittorrent, homekase.fish runner).
- [x] **Immich DB password fallback**: Now auto-generates with `openssl rand -base64 24` if user skips prompt.
- [x] **DB password printed to stdout in `homekase create`**: Now points user to `.env` file instead.

### Network / Access
- [x] **Traefik dashboard exposed without authentication**: Now has auto-generated basic auth credentials.
- [ ] **No TLS anywhere**: all services on plain HTTP. Add Let's Encrypt (for public) or self-signed cert option (for LAN).
- [ ] **AdGuard initial setup on port 3000 with no auth**: first-access wizard is open to anyone on the network. Race condition — someone else could configure it first.
- [ ] **qBittorrent default credentials `admin/adminadmin`**: warn message is not enough. Consider auto-generating password and writing to `.env`.
- [x] **Port 53 open to all interfaces**: Documented as intentional in adguard.sh compose.

### Container Security
- [x] **Docker socket mounted in GitHub runner**: Documented risk in compose. Consider Docker-in-Docker or Sysbox for better isolation.
- [x] **GitHub runner image unpinned**: Now pinned to 2.319.1.
- [x] **All service images use `latest`**: All pinned to specific versions.

### SSH / System
- [ ] **No SSH hardening**: no fail2ban, no key-only auth enforcement, no `PermitRootLogin no` check. Consider adding as optional step.
- [ ] **`curl | sudo bash` pattern**: inherent risk (standard in the ecosystem, but worth documenting). The script does clone to temp dir first which is good.

## Idempotency — ALL FIXED
- [x] **`config.fish` appended every run**: Now writes to `conf.d/homekase.fish` with overwrite.
- [x] **`urls.txt` appended every deploy**: Now uses `append_url` helper with dedup.
- [x] **`/etc/fstab` appended without dedup**: Now checks before appending + backs up fstab.
- [x] **`ufw --force reset` on every run**: Now checks existing rules, prompts before applying.
- [x] **`install_shell_tools` re-downloads everything**: Now guarded with `is_installed`.
- [x] **`install_neovim` re-downloads nvim**: Now guarded with `is_installed`.
- [ ] **`install_base_packages` re-runs apt install**: harmless but slow. Low priority.

## Disk Operations — ALL FIXED
- [x] **No blank-disk check before LVM**: Shows existing partitions, requires confirmation.
- [x] **No fstab backup**: Backs up to fstab.bak.
- [x] **80% LVM allocation hardcoded**: Explained to user.
- [x] **No error handling if pvcreate fails**: Catches failure with actionable message.

## Package Management
- [ ] **Migrate lazygit to apt/repo install**: currently binary download. Consider apt repo.
- [ ] **Migrate yazi to apt/repo install**: same as lazygit.

## Robustness
- [x] **No app name validation**: Now validates `[a-z0-9-]` only.
- [x] **`get_home()` uses `eval echo ~user`**: Now uses `getent passwd`.
- [x] **No pre-flight check for required commands**: Now checks curl, git, lsblk, findmnt, openssl.

## Testing
- [ ] **Tests only mock deploy functions**: no real Docker stack validation.
- [ ] **Docker integration test only validates dry-run**: not actual deployment.
- [x] **Custom `test_helper.bash`**: Added `assert_equal`.

## Templates
- [ ] **`package.json` no version pinning**: dependencies use exact versions but no lock file strategy.
- [x] **GitHub Actions deploy workflow hardcodes `localhost`**: Now tries container name first with fallback.

---

## UX / Wizard Flow — MOSTLY DONE

### High Priority — ALL DONE
- [x] **`configure_firewall`**: Section + confirmation prompt.
- [x] **`set_fish_default`**: Explains fish + asks before changing.
- [x] **`deploy_adguard`**: Explains + asks before deploying.

### Tool Selection Menus — ALL DONE
- [x] **Terminal editor selection**: prompt_choose (LazyVim or skip)
- [x] **Git TUI selection**: prompt_choose (lazygit or skip)
- [x] **Shell prompt selection**: prompt_choose (Starship or skip)
- [x] **File manager selection**: prompt_choose (yazi or skip)
- [x] **Terminal multiplexer selection**: prompt_choose (zellij or skip)

### General Wizard Improvements — ALL DONE
- [x] **Welcome/overview step**: Shows summary before starting.
- [x] **Step numbering**: Step N/10 progress indicators.
- [x] **Brief explanations**: system_update and docker install now explain themselves.

### Remaining
- [ ] **No TLS anywhere**: needs cert infrastructure decisions.
- [ ] **SSH hardening**: optional step, complex.
- [ ] **qBittorrent auto-generate password**: needs qBit API.
- [ ] **AdGuard first-access auth race**: upstream limitation.
- [ ] **Migrate lazygit/yazi to apt repos**: convenience improvement.
- [ ] **Real Docker integration tests**: requires Docker in test env.
