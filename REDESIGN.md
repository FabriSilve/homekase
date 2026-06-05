# REDESIGN — homekase v2: CLI Tool, Not a Setup Script

## Why

The v1 "one-shot sequential setup" approach failed because:
- A single error mid-way kills the whole run
- Hard to debug what went wrong
- Can't cherry-pick individual steps
- Re-runs are confusing (skip vs redo logic)
- Services deployed but not properly configured (e.g., Beszel with no agent, AdGuard with no DNS rewrites, HTTPS redirection with no matching routers)

## New Vision

`homekase` is a **modular CLI tool** — like `brew` or `gh` but for homelab tasks. Each command is independent, idempotent, and self-contained.

No more `curl | sudo bash`. You clone the repo and run individual commands as needed.

## Command Structure

```
homekase                          # Opens interactive TUI menu
homekase system update            # apt update + upgrade
homekase system ssh-hardening     # SSH key-only + fail2ban
homekase system swap              # Configure swap file
homekase system firewall          # UFW rules

homekase disk setup               # Interactive LVM/partition setup
homekase disk reset               # Wipe homelab mount points

homekase docker install           # Docker + Compose
homekase docker prune             # Clean up old images

homekase service add <name>       # Deploy a service by name (jellyfin, immich, etc.)
homekase service remove <name>    # Tear down a service
homekase service list             # Show available + deployed services
homekase service logs <name>      # Tail logs for a service
homekase service update <name>    # Pull + restart a single service

homekase app create <name>        # Scaffold new app from template
homekase app deploy <name>        # Build + push + deploy
```

## What to Drop

| Component | Why |
|-----------|-----|
| **AdGuard Home** | Adds complexity (port 53 conflicts, DNS rewrites). Use Tailscale DNS or `/etc/hosts` instead. |
| **Traefik** | Overkill for a homelab. Each service runs on its own port, or use Tailscale Serve/Funnel. |
| **Self-signed TLS** | Unnecessary without Traefik. Services run on plain HTTP on LAN. |

## What to Keep

| Component | How |
|-----------|-----|
| **Tailscale** | Primary access method. Tailscale Serve for `*.home` routing via MagicDNS. No more DNS rewrites, no more port conflicts. |
| **Docker Compose** | Each service in `/opt/homelab/<name>/docker-compose.yml`. No Traefik labels needed. |
| **Fish CLI** | `homekase` commands are fish functions that source bash libs as needed. |
| **Service configs** | Immich, Jellyfin, qBittorrent, Syncthing, Beszel — same configs, no reverse proxy wrapping. |

## How Access Works (New)

### LAN
- Each service exposes a unique port
- `http://192.168.1.171:8096` → Jellyfin
- `http://192.168.1.171:8384` → Syncthing
- etc.
- Bookmark or use `/etc/hosts` aliases if desired

### Remote (via Tailscale)
- Same ports, accessible over Tailscale IP
- `http://100.112.115.120:8096` → Jellyfin from phone
- Optionally: **Tailscale Serve** to bind friendly names
  - `tailscale serve --https=443 8096` → `http://jellyfin.tailXXXXX.ts.net`
  - Or use Tailscale Funnel for public internet access

## Directory Layout

```
~/.local/share/homekase/
├── repos/                    # Cloned service repos
│   ├── server-assistant/
│   └── ...
└── config/                   # User preferences

/opt/homelab/
├── <name>/                   # Each service in its own dir
│   ├── docker-compose.yml
│   ├── .env                  # Secrets generated per service
│   └── data/                 # Persistent data
└── ...
```

## File Structure

```
homekase/
├── homekase.fish             # Entry point — dispatches to subcommands
├── lib/
│   ├── system.fish           # system commands
│   ├── disk.fish             # disk commands
│   ├── docker.fish           # docker commands
│   ├── service.fish          # service add/remove/list/logs/update
│   └── app.fish              # app create/deploy
├── services/                 # Service definitions
│   ├── jellyfin.sh           # Function that writes docker-compose.yml
│   ├── immich.sh
│   ├── qbittorrent.sh
│   └── ...
└── README.md
```

## Migration Plan

1. Rewrite `homekase.fish` as the main CLI dispatcher
2. Create subcommand modules (system, disk, docker, service, app)
3. Drop AdGuard, Traefik, and certs from all service templates
4. Each service gets a unique port, no reverse proxy
5. Add `homekase service add` flow that picks a free port
6. Test with Tailscale Serve as the access layer
7. Document the new port map and access patterns
