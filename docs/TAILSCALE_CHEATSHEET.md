# Tailscale Cheatsheet — homekase

## Setup

```bash
# Install
curl -fsSL https://tailscale.com/install.sh | sh

# Auth & connect
sudo tailscale up

# Re-auth (e.g. after a new device)
sudo tailscale up --force-reauth

# With MagicDNS (lets you use hostnames instead of IPs)
sudo tailscale up --accept-dns
```

## Status & Info

```bash
tailscale status              # List connected devices
tailscale ip -4               # Your Tailscale IPv4
tailscale ip -6               # Your Tailscale IPv6
tailscale netcheck            # Check NAT/connectivity
tailscale version             # Tailscale version
tailscale whois <ip>          # Show device info for a given IP
```

## Expose a Docker Compose Service via Tailscale Serve

### Step 1: Check the port your service runs on

Look in your `docker-compose.yml` for the published port, e.g.:

```yaml
ports:
  - "8096:8096"   # Jellyfin
```

The host port (left of `:`) is what you use.

### Step 2: Serve it

```bash
# Basic HTTPS serve
sudo tailscale serve --https=443 8096
# Now accessible at: https://homekase.tailxxxxx.ts.net (or whatever your hostname is)

# You can add --bg to run in background
sudo tailscale serve --https=443 --bg 8096
```

### Step 3: Check what's being served

```bash
tailscale serve status
```

### Step 4: Remove a serve entry

```bash
sudo tailscale serve --https=443 off
```

## Serve Multiple Services

Each service needs its own subpath or its own port:

```bash
# Via different ports (cleaner)
sudo tailscale serve --https=8443 8096    # Jellyfin
sudo tailscale serve --https=8444 8384    # Syncthing
# → https://homekase.tailxxxxx.ts.net:8443
# → https://homekase.tailxxxxx.ts.net:8444

# Via subpaths (single port, use --set-path flag)
sudo tailscale serve --https=443 --set-path=/jellyfin  http://127.0.0.1:8096
sudo tailscale serve --https=443 --set-path=/syncthing http://127.0.0.1:8384
# → https://homekase.tailxxxxx.ts.net/jellyfin
# → https://homekase.tailxxxxx.ts.net/syncthing
```

### Expose to the Internet (Funnel)

```bash
# Public internet access (requires Tailscale Funnel enabled in admin console)
sudo tailscale funnel --https=443 8096
```

> **Warning**: Funnel bypasses your tailnet — anyone with the URL can access it.

## MagicDNS (Friendly Hostnames)

With `--accept-dns` enabled during `tailscale up`:

```bash
# Instead of https://100.118.198.93:8096
# You get: https://homekase.tailxxxxx.ts.net:8096
```

Find your full hostname:
```bash
tailscale status | head -1 | awk '{print $2".tail"$(NF-1)".ts.net"}'
# Or just look in the Tailscale admin console
```

## Quick Test — Beszel Monitoring (Docker Compose, no Traefik)

```bash
# Create dir
sudo mkdir -p /opt/homelab/beszel

# Compose file (no labels, no reverse proxy)
sudo tee /opt/homelab/beszel/docker-compose.yml << 'EOF'
services:
  beszel:
    image: henrygd/beszel:latest
    restart: unless-stopped
    ports:
      - "8090:8090"
    volumes:
      - ./data:/opt/beszel
EOF

# Start it
sudo docker compose -f /opt/homelab/beszel/docker-compose.yml up -d

# Expose via Tailscale
sudo tailscale serve --https=443 --bg 8090

# Access: https://homekase.tailxxxxx.ts.net
```

## Useful Commands

```bash
tailscale logout                          # Log out of tailnet
tailscale up --accept-routes              # Accept subnet routes (if configured)
tailscale ping 100.x.x.x                  # Test connectivity to device
tailscale file cp <file> 100.x.x.x:       # Send file to device
```

## Debugging

```bash
journalctl -u tailscaled -n 50 --no-pager   # Tailscale daemon logs
sudo tailscale debug                        # Debug commands
tailscale bugreport                          # Generate bug report
```

## DNS Quick Fixes

If you don't want to run AdGuard:

```bash
# 1. Use Tailscale MagicDNS (simplest)
sudo tailscale up --accept-dns

# 2. Or just use /etc/hosts for LAN names
echo "192.168.1.171 jellyfin.home" | sudo tee -a /etc/hosts

# 3. Or use systemd-resolved (no extra containers)
resolvectl domain eth0 "~home"
resolvectl dns eth0 192.168.1.171
```
