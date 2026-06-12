# TO_DISCUSS

Open questions to review before or during Plans 2–5.

---

## Plan 2 — Server Commands

**1. UFW port list**
Current plan opens 22 (SSH), 80 (HTTP), 443 (HTTPS). With Traefik dropped and no web services exposed directly, do we still need 80/443 open in UFW? Or only open ports per service as they're added (e.g., 8096 for Jellyfin)?
Suggestion: start with SSH only + allow tailscale0, then `homekase add <service>` opens the specific port if Tailscale Serve is NOT used.

**2. Static IP — DNS field**
Old setup pointed nameservers at 127.0.0.1 (AdGuard). With AdGuard dropped, netplan should point to a real DNS (e.g., 1.1.1.1, 8.8.8.8) or leave DHCP DNS. What's your preference?

**3. `homekase server docker` vs `homekase init`**
Agreed docker install moves to `homekase server docker`. But `homekase init` installs other tools (fzf, bat, etc.) — should `homekase server docker` be runnable standalone before `homekase init`? Answer is probably yes, since docker is a server prereq, not a dev tool.

---

## Plan 3 — Init Command

**4. gum bootstrap problem**
`homekase init` uses `gum` for the multi-select tool list. But `gum` is one of the tools being installed by `homekase init`. First run has no gum.
Options:
  a. Install gum first silently, then show the interactive list (current plan lean)
  b. Show a plain numbered list if gum not available, upgrade to gum UI after install
  c. Require user to install gum manually before running `homekase init`
Option (a) is cleanest UX. Confirm?

**5. nvim shared config symlink**
Plan: install LazyVim to `/opt/homekase/nvim`, symlink `~/.config/nvim` → `/opt/homekase/nvim` for invoking user + root.
Question: should this apply to ALL existing users on the system, or only the user who runs `homekase init` + root?

---

## Plan 4 — Services

**6. Service port conflicts**
If multiple services use port 8080 (qBittorrent default, Filebrowser default, AI assistant), `homekase add` wizard needs to detect port conflicts and suggest alternatives.
Plan: check `ss -tlnp` or `/etc/homekase/homekase.yml` port registry before assigning.

**7. Tailscale Serve — one port per machine**
`tailscale serve` on HTTPS 443 can only point to one backend per machine (unless using path-based routing). If user installs Jellyfin on 8096 AND Immich on 3001 and wants both via Tailscale Serve, they'd need different machine hostnames or path routing.
Clarify: is Tailscale Funnel / Serve with path prefixes acceptable? Or stick to direct port access over Tailscale IP and only offer Serve as optional for one "primary" service?

**8. AI Assistant RAM check thresholds**
Old thresholds: 14b model needs 12GB RAM, 7b needs 7GB, 3b needs 4GB.
Should these stay the same, or do you want to revisit model choices (e.g., newer Qwen/Llama versions)?

---

## Plan 5 — Status + Backup

**9. `homekase status` — which docker socket?**
`docker ps` requires either root or the user to be in the `docker` group. If `homekase status` is run as a non-root user not in the docker group, the service table will be empty.
Options: require root for status, or document that user needs to be in docker group.

**10. Backup destination default**
Agreed default is `/backup`. But the config template has `paths.backup: /backup` (no 's'). Old setup used `/backups`. Confirm `/backup` is correct.

**11. Incremental backup via rsync hardlinks**
This works well for file-based data. For Postgres containers, we need `pg_dump` before the rsync. The plan identifies Immich as the main Postgres user. Are there others (Vikunja uses SQLite — no dump needed)? Confirm which installed services have Postgres.
