# homekase

Opinionated homelab CLI for Ubuntu Server 24.04 LTS. Modular, idempotent, no curl-pipe-bash.

Inspired by [Omakub](https://github.com/basecamp/omakub).

## What you get

- **Shell tools**: fish, starship, lazygit, fzf, btop, neovim, and more — installed à la carte via `homekase init`
- **Containers**: Docker + Docker Compose per service, no shared reverse proxy
- **Remote access**: Tailscale (MagicDNS + Serve for HTTPS on your tailnet)
- **Firewall**: UFW with per-service open/close via `homekase open/close`
- **Services**: Jellyfin, Immich, qBittorrent, Filebrowser, Vikunja, local AI (Ollama, Colibrí)
- **CLI**: `homekase` — install, manage, inspect, and back up everything

## Hardware requirements

| Component     | Minimum    | Recommended |
| ------------- | ---------- | ----------- |
| CPU           | 2 cores    | 4+ cores    |
| RAM           | 8 GB       | 16-32 GB    |
| OS drive      | 120 GB SSD | 250 GB SSD  |
| Data drive    | —          | 500 GB SSD  |
| Storage drive | —          | 1 TB+ HDD   |

## Installation

SSH into your server, then:

```bash
curl -fsSL https://raw.githubusercontent.com/FabriSilve/homekase/master/install.sh | sudo bash
```

`install.sh` installs prerequisites (git, yq, gum), generates an SSH key, clones the repo to `/opt/homekase`, symlinks `homekase` to `/usr/local/bin`, and initialises the config at `/etc/homekase/homekase.yml`.

You will be prompted to add the generated SSH public key to your GitHub account before the clone happens.

## First-time setup

Run these once after installation, in any order:

```bash
homekase init                  # pick and install shell tools interactively
homekase server docker         # install Docker engine + create homekase-net bridge
homekase server firewall setup # configure UFW with sane defaults
homekase server vpn            # install Tailscale and enable MagicDNS
```

## Commands

### Services

```bash
homekase list                  # browse available and installed services
homekase add <service>         # deploy a service (interactive port + Tailscale prompt)
homekase remove <service>      # stop and optionally delete a service
```

Available services: `jellyfin`, `immich`, `qbittorrent`, `filebrowser`, `vikunja`, `assistant`, `colibri`

### Firewall

```bash
homekase open <service>        # expose service port in UFW (LAN testing)
homekase close <service>       # remove UFW rule for the service
```

### Operations

```bash
homekase status                # system stats + all running services with URLs
homekase status --json         # machine-readable output
homekase backup                # snapshot data and databases for all services
homekase backup <service>      # snapshot a specific service
homekase update                # pull latest homekase from GitHub
homekase uninstall             # remove homekase CLI (keeps /data, /storage, /backup)
```

### Server setup

```bash
homekase server ssh            # harden SSH (key-only login, fail2ban)
homekase server firewall       # manage UFW rules
homekase server network        # show network interfaces and gateway
homekase server vpn            # install/configure Tailscale
homekase server swap           # create 6 GB swap with swappiness=10
homekase server disk           # show disk layout and usage
homekase server docker         # install Docker engine and create homekase-net
```

## Access

Each service runs on a port you choose during `homekase add`. No shared reverse proxy.

| Context                             | URL                                          |
| ----------------------------------- | -------------------------------------------- |
| Local network                       | `http://<server-ip>:<port>`                  |
| LAN by name (after `homekase open`) | `http://<server-ip>:<port>`                  |
| Remote (Tailscale)                  | `https://<hostname>.<tailnet>.ts.net:<port>` |

Run `homekase status` to list all running services with their URLs.

## Directory layout

```
/opt/homekase/
├── jellyfin/
│   ├── docker-compose.yml
│   └── .env
├── immich/
│   ├── docker-compose.yml
│   └── .env
└── ...

/data/           # fast SSD — databases, config files
/storage/        # large HDD — media, photos, torrents
/backup/         # snapshots created by homekase backup
/etc/homekase/
└── homekase.yml # CLI state: installed services, ports, paths
```
