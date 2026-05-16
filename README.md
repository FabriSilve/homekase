# 🏠 homekase

Homelab setup for Ubuntu Server 24.04 LTS. Opinionated, automated, idempotent.

Inspired by [Omakub](https://github.com/basecamp/omakub).

## What you get

- **Shell**: fish, starship, zellij, lazygit, fzf, yazi
- **Editor**: Neovim + LazyVim
- **Containers**: Docker + Docker Compose
- **Reverse proxy**: Traefik (auto-routes `*.home` to your services)
- **DNS + ad blocking**: AdGuard Home
- **Storage**: LVM on separate drives with expansion room
- **Services**: Jellyfin, Immich, qBittorrent, Syncthing, Beszel, GitHub runners
- **CLI**: `homekase` fish function to create apps, update, and check status

## Phase 0: Install Ubuntu Server

### Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 8 GB | 16-32 GB |
| OS drive | 120 GB SSD | 250 GB SSD |
| Data drive | — | 500 GB SSD |
| Storage drive | — | 1 TB+ HDD |

### Installation

1. Download [Ubuntu Server 24.04 LTS](https://ubuntu.com/download/server)
2. Flash to USB: `dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/sdX bs=4M`
3. Boot from USB on your server
4. In the installer:
   - **Language**: your preference
   - **Keyboard**: your layout
   - **Network**: choose wired connection, note the IP
   - **Proxy**: leave blank
   - **Mirror**: default
   - **Storage**: select your OS drive (250 GB SSD)
     - Use **entire disk**
     - **Do NOT enable LVM** (keep it simple for the OS disk)
   - **Profile**: create your user and hostname
   - **SSH**: enable **Install OpenSSH server**
   - **Snaps**: skip all optional snaps
5. Wait for installation to complete
6. Reboot and remove USB
7. Your server is ready

## Phase 1: Run homekase

```bash
ssh youruser@192.168.x.x
bash <(curl -fsSL https://raw.githubusercontent.com/you/homekase/main/setup.sh)
```

The script will guide you through:
- System update
- Tool installation (fish, neovim, lazygit, fzf, yazi, gh, etc.)
- Disk selection and LVM setup for `/data` and `/storage`
- Docker + Traefik + AdGuard Home
- Service selection menu
- Summary with access URLs

## Usage

```bash
# Create a new app
homekase create my-app

# Re-run setup (idempotent — safe to run anytime)
homekase update

# Check system status
homekase status
```

## Directory Layout

```
/opt/homelab/
├── traefik/          # Reverse proxy
├── monitoring/       # Beszel dashboard
├── apps/             # Your custom apps
│   └── my-app/
│       ├── docker-compose.yml
│       ├── api/
│       ├── frontend/
│       └── .github/workflows/deploy.yml
├── jellyfin/         # Media server
├── immich/           # Photo backup
├── qbittorrent/      # Torrent client
├── syncthing/        # File sync
├── github-runner/    # CI/CD runners
└── urls.txt          # Service URLs

/data/                # Fast SSD — databases, configs
/storage/             # Large HDD — media, photos, torrents
```

## URL Map

| URL | Service |
|-----|---------|
| `http://dashboard.home` | Traefik dashboard |
| `http://dns.home` | AdGuard Home |
| `http://monitoring.home` | Beszel monitoring |
| `http://jellyfin.home` | Jellyfin media |
| `http://photos.home` | Immich photos |
| `http://torrent.home` | qBittorrent |
| `http://sync.home` | Syncthing |
| `http://<app>.home` | Your apps |

## DNS for *.home

To access services by name, configure your router's DHCP to advertise your server's IP as the DNS server (AdGuard Home handles resolution). Or add entries to each device's `/etc/hosts`:

```
192.168.x.x  dashboard.home dns.home monitoring.home jellyfin.home photos.home torrent.home sync.home
```
