# DEV.md — homekase Developer Guide

## Vision

An opinionated, idempotent, single-command homelab setup for Ubuntu Server 24.04 LTS. From a fresh Ubuntu install to a fully running Jellyfin + Immich + qBittorrent + monitoring + custom app hosting in one session.

Inspired by [Omakub](https://github.com/basecamp/omakub).

### Principles

- **Idempotent** — run it 10 times, same result, no data loss
- **Choose your stack** — service selection menu, not everything-or-nothing
- **CLI, not UI** — fish functions for day-to-day management
- **No vendor lock-in** — Docker Compose, no cloud dependencies
- **Dev-friendly** — self-hosted GitHub runners, scaffolded app template, CI/CD baked in

---

## Project Structure

```
homekase/
├── setup.sh                        # Entry point — curl | sudo bash
├── Makefile                        # make lint | test | dry-run | docker-test
├── .shellcheckrc                   # ShellCheck config
├── README.md                       # End-user install guide
├── DEV.md                          # This file
│
├── lib/                            # Bash modules, sourced by setup.sh
│   ├── common.sh                   # Colors, prompts, helpers (info, ok, warn, error)
│   ├── system.sh                   # apt update, base packages, firewall
│   ├── disks.sh                    # lsblk detection, LVM setup, mount
│   ├── tools.sh                    # fish, zellij, lazygit, fzf, yazi, gh, nvim
│   ├── users.sh                    # fish default shell, starship, config.fish
│   ├── docker.sh                   # Docker + Compose install
│   ├── traefik.sh                  # Traefik reverse proxy
│   ├── adguard.sh                  # AdGuard Home DNS + ad blocking
│   ├── services.sh                 # Service selection menu + dispatcher
│   ├── jellyfin.sh                 # Media server at jellyfin.home
│   ├── immich.sh                   # Photo backup at photos.home
│   ├── qbittorrent.sh              # Torrent client at torrent.home (+ VPN)
│   ├── syncthing.sh                # File sync at sync.home
│   ├── beszel.sh                   # Monitoring at monitoring.home
│   └── github-runner.sh            # Self-hosted CI/CD runners
│
├── functions/
│   └── homekase.fish               # Fish CLI: create, update, status
│
├── templates/
│   └── app/                        # Scaffold template for new projects
│       ├── docker-compose.yml      # API + DB + frontend + Traefik labels
│       ├── api/                    # Express + pg healthcheck endpoint
│       ├── frontend/               # nginx serving SPA with API test
│       └── .github/workflows/
│           └── deploy.yml          # GitHub Actions deploy workflow
│
└── tests/
    ├── test_common.bats            # Tests for common.sh
    ├── test_disks.bats             # Tests for disks.sh
    ├── test_services.bats          # Tests for services.sh
    ├── test_helper.bash            # Minimal bats assertions
    ├── run_shellcheck.sh           # ShellCheck runner
    ├── run_tests.sh                # Full test runner
    ├── Dockerfile.test             # Ubuntu 24.04 integration test
    └── docker-compose.test.yml     # Docker Compose for integration test
```

### Architecture Overview

```
┌─ curl | sudo bash ─────────────────────────────┐
│  setup.sh                                       │
│    ├── lib/common.sh       (helpers, prompts)    │
│    ├── lib/system.sh       (os, packages)        │
│    ├── lib/disks.sh        (LVM, mounts)         │
│    ├── lib/tools.sh        (shell, editors)      │
│    ├── lib/docker.sh       (docker + compose)   │
│    ├── lib/traefik.sh      (reverse proxy)       │
│    ├── lib/adguard.sh      (dns + ads)          │
│    ├── lib/services.sh     (selection menu)      │
│    ├── lib/jellyfin.sh     (media)               │
│    ├── lib/immich.sh       (photos)              │
│    ├── lib/qbittorrent.sh  (torrents)            │
│    ├── lib/syncthing.sh    (file sync)           │
│    ├── lib/beszel.sh       (monitoring)          │
│    └── lib/github-runner.sh (ci/cd)             │
│                                                   │
│  Installs to /opt/homelab/                        │
│  Installs homekase fish function                  │
└───────────────────────────────────────────────────┘

┌─ homekase <command> ──────────────────────────┐
│  create <name>    → scaffolds app from template │
│  update            → re-runs setup.sh          │
│  status            → shows services + resources │
└─────────────────────────────────────────────────┘
```

### URL Map

| URL | Service | Lib module |
|-----|---------|-----------|
| `dashboard.home` | Traefik dashboard | traefik.sh |
| `dns.home` | AdGuard Home | adguard.sh |
| `monitoring.home` | Beszel | beszel.sh |
| `jellyfin.home` | Jellyfin | jellyfin.sh |
| `photos.home` | Immich | immich.sh |
| `torrent.home` | qBittorrent | qbittorrent.sh |
| `sync.home` | Syncthing | syncthing.sh |
| `<app>.home` | Your custom apps | app template |

---

## Development Workflow

### First time

```bash
git clone https://github.com/FabriSilve/homekase
cd homekase

# Install dev dependencies (check only — no apt)
make setup-dev

# Validate everything that can run locally
make check
```

### Dev loop

```bash
# 1. Edit a lib module
vim lib/jellyfin.sh

# 2. Validate syntax
make bash-check

# 3. Run related unit tests
bats tests/test_services.bats

# 4. Dry-run (preview without executing)
sudo make dry-run

# 5. Full validation
make check
```

### Run tests

```bash
make test       # Bats unit tests only
make lint       # ShellCheck + syntax checks
make check      # lint + test
make all        # lint + test + Docker integration
```

### Docker integration test

```bash
# Build and run the full setup in an Ubuntu 24.04 container
make docker-test

# Or step by step:
docker compose -f tests/docker-compose.test.yml build
docker compose -f tests/docker-compose.test.yml run --rm homekase-test
docker compose -f tests/docker-compose.test.yml down
```

---

## Testing with Multipass (Recommended)

Multipass is a Canonical tool that launches Ubuntu VMs in seconds — no ISO, no installer, no clicks.

### Installation

**Arch:**
```bash
yay -S multipass
# or
paru -S multipass
```

**Ubuntu/Debian:**
```bash
sudo snap install multipass
```

### Quick test loop

```bash
# Launch a test VM
multipass launch 24.04 --name homekase-test --cpus 2 --memory 4G --disk 20G

# Get a shell inside
multipass shell homekase-test

# Inside the VM — install git and clone your branch
sudo apt update && sudo apt install -y git
git clone -b your-branch https://github.com/FabriSilve/homekase /tmp/homekase
cd /tmp/homekase

# Run the setup (dry-run first to preview)
sudo bash setup.sh --dry-run | less

# Run for real
sudo bash setup.sh

# Exit and destroy when done
exit
multipass delete --purge homekase-test
```

### Iterating

```bash
# After making changes to the code:
# 1. Destroy old VM
multipass delete --purge homekase-test

# 2. Launch fresh
multipass launch 24.04 --name homekase-test --cpus 2 --memory 4G --disk 20G

# 3. Copy your local code into the VM
multipass mount /path/to/homekase homekase-test:/homekase

# 4. Run
multipass exec homekase-test -- sudo bash /homekase/setup.sh

# Or mount your repo and run repeatedly without re-cloning
multipass mount $PWD homekase-test:/homekase
multipass exec homekase-test -- sudo bash /homekase/setup.sh --dry-run
```

### Testing the install command (curl | bash)

```bash
# Push your branch first, then inside the VM:
curl -fsSL https://raw.githubusercontent.com/FabriSilve/homekase/your-branch/setup.sh | sudo bash
```

---

## Testing with Other VMs

### libvirt/QEMU (if you have omarchy)

```bash
sudo pacman -S virt-manager qemu-desktop libvirt dnsmasq
sudo systemctl enable --now libvirtd
virt-manager
# Create: Ubuntu 24.04, 2 cores, 4 GB RAM, 20 GB disk
# Boot ISO → install → ssh in → run setup
```

### VirtualBox

```bash
sudo pacman -S virtualbox virtualbox-host-modules-arch
# VM: 2 cores, 4 GB RAM, 20 GB disk, bridged network
# Install Ubuntu Server → test
```

### Docker (limited, but fast)

The Docker integration test validates core logic but can't test system-level operations (LVM, firewall, systemd).

```bash
make docker-test
```

---

## Making Changes

### Adding a new service

1. Create `lib/your-service.sh` with a `deploy_your_service()` function
2. Write a compose file inline (heredoc) that includes Traefik labels
3. Add to the selection menu in `lib/services.sh`
4. Add an entry in `setup.sh`'s `main()` function
5. Add the URL to `generate_summary()` and the README

### Modifying the app scaffold

Edit files in `templates/app/`. The `homekase create` command copies them and substitutes `{{APP_NAME}}` placeholders.

### Updating the fish function

Edit `functions/homekase.fish`. Validate with `make fish-check`.

### Adding a Makefile target

A typical pattern:

```makefile
.PHONY: my-target
my-target:
	@echo ":: Doing something..."
	@# bash commands here
```

---

## Idempotency Rules

| Operation | Guard | Behavior |
|-----------|-------|----------|
| `apt install` | `dpkg -l` | Skip if version matches |
| Fish config | `~/.config/fish/` | Append, never overwrite |
| Starship | `~/.config/starship.toml` | Skip if exists |
| LazyVim | `~/.config/nvim/` | Skip if exists |
| Docker | `docker --version` | Skip if installed |
| LVM /data | `mount \| grep /data` | Skip if mounted |
| Services | `/opt/homelab/<name>/` dir | Skip if directory exists |
| Traefik | `docker compose ls` | Skip if running |

---

## Key Conventions

- **Shell**: Bash for `lib/*.sh`, Fish for `functions/homekase.fish`
- **Prompts**: Use `prompt_yes_no`, `prompt_input`, `prompt_secret` from `common.sh`
- **Messaging**: Use `info`, `ok`, `warn`, `error` from `common.sh`
- **Each service in its own dir** under `/opt/homelab/`
- **Traefik routing via Docker labels** — no config file editing
- **DBs exposed only within their compose network** — never on the host/wifi
