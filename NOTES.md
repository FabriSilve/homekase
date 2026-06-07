# Notes

- did update and upgrade for apt
- the neovim package exist in the apt store, no need for curl
- i then callee
  > sudo apt install git ca-certificates curl wget unzip software-properties-common gnupg ufw
- then I followed the firewall steps
  > ufw --force reset
  > ufw default deny incoming
  > ufw default allow outgoing
  > ufw allow ssh
  > ufw allow 80/tcp
  > ufw allow 443/tcp
  > ufw allow 53/udp
  > ufw --force enable

- followed hardening steps
- installed tailscale and login to it + up
- then isntalled all the shell tools package
- installed zellij from url and lazygit from apt install
- skipped yazi
- installed lazydocker from url
- installed gh cli with installation steps
- cloned lazyvim repo
- installed zoxide for folders navigation
- setup fish, zoxide and starfish
- installed docker with docs steps
- setup limit logs docker
- setup swap 6G
- test serving wekan with tailscale subpath (stripped via `--set-path`) but app didn't support it
- settled on port-based Tailscale Serve instead: `sudo tailscale serve --https=8443 --bg 8081`

## Standard flow to install a Docker Compose app

```bash
# 1. Create app dir
sudo mkdir -p /opt/<service>/data

# 2. Write compose file with:
services:
  app:
    image: ...
    restart: unless-stopped
    ports:
      - "<host-port>:<container-port>"
    volumes:
      - /data/<service>:/path/in/container  # DBs, configs
      - /storage/<service>:/path            # Media, files, torrents
    environment:
      - ROOT_URL=https://homekase.tail5afc87.ts.net:<serve-port>

# 3. Start
sudo docker compose -f /opt/<service>/docker-compose.yml up -d

# 4. Expose via Tailscale Serve (unique port per service)
sudo tailscale serve --https=<serve-port> --bg <host-port>
```

## Conventions

- **App dirs**: `/opt/<service>/` — root-owned, contains docker-compose.yml and .env
- **Data**: `/data/<service>/` for persistent data (DBs, configs)
- **Media/files**: `/storage/<service>/` for large files (Jellyfin media, torrents, etc.)
- **Root ownership is correct** — Docker runs as root, compose files are infra config
- **Each service gets its own Tailscale Serve port** (e.g. 8443, 8444, 8445) since subpath routing doesn't work with most apps




