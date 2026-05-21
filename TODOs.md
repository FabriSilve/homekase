# TODOs — Status

All major items resolved. Remaining items are minor or intentional.

## Security — ALL DONE
- [x] Secrets moved to `.env` files (immich, github-runner, qbittorrent, fish runner)
- [x] Immich DB password auto-generates if empty
- [x] DB password no longer printed to stdout
- [x] Traefik dashboard has basic auth
- [x] Optional self-signed TLS for LAN HTTPS
- [x] AdGuard pre-seeded with admin credentials (no open wizard race)
- [x] qBittorrent password auto-generated
- [x] Port 53 documented as intentional
- [x] Docker socket risk documented
- [x] All images pinned to versions
- [x] Optional SSH hardening (root login, key-only, fail2ban)

## Idempotency — ALL DONE
- [x] config.fish → conf.d with overwrite
- [x] urls.txt dedup via append_url
- [x] fstab dedup + backup
- [x] Firewall checks existing rules
- [x] All tool installs guarded with is_installed
- [ ] `install_base_packages` re-runs apt install (harmless, low priority)

## Disk Operations — ALL DONE
- [x] Blank-disk check with lsblk -f
- [x] fstab backup
- [x] 80% LVM explained to user
- [x] pvcreate error handling

## Robustness — ALL DONE
- [x] App name validation [a-z0-9-]
- [x] get_home() uses getent
- [x] Pre-flight command checks

## UX / Wizard — ALL DONE
- [x] Optional gum-based wizard UI
- [x] Firewall, fish, AdGuard all have prompts
- [x] Tool selection menus (editor, git TUI, file manager, prompt, multiplexer)
- [x] Welcome overview + step numbering
- [x] Brief explanations for all steps

## Testing — IMPROVED
- [x] Compose validation tests (7 tests for all services)
- [x] assert_equal added to test helper
- [x] Deploy workflow health check fixed
- [ ] Real Docker-in-Docker integration tests (requires Docker in CI)

## Package Management — INTENTIONAL
- lazygit: no official apt repo. Binary download is recommended install method.
- yazi: no official apt repo. Binary download is recommended install method.

## Remaining (Won't Fix / Deferred)
- [ ] `curl | sudo bash` pattern: inherent risk, standard in ecosystem, documented
- [ ] Real Docker integration tests: requires Docker in test env (CI improvement)
