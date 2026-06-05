function homekase -d "Manage your homekase homelab"
    set -l HOMELAB_DIR /opt/homelab
    set -l REPO_URL "https://github.com/FabriSilve/homekase.git"
    set -l URLS_FILE "$HOMELAB_DIR/urls.txt"

    switch "$argv[1]"
        case create
            if test (count $argv) -lt 2
                echo "Usage: homekase create <app-name>"
                return 1
            end
            __homekase_create_app $argv[2]

        case update
            __homekase_update

        case status
            __homekase_status

        case backup
            if test (count $argv) -ge 2
                homekase-backup $argv[2]
            else
                homekase-backup run
            end

        case ""
            echo "Usage: homekase {create|update|status|backup}"
            echo ""
            echo "  create <name>     Scaffold a new app"
            echo "  update            Re-run setup (idempotent)"
            echo "  status            Show resources, services, and URLs"
            echo "  backup [status]   Run backups or show backup status"

        case '*'
            echo "Unknown command: $argv[1]"
            echo "Usage: homekase {create|update|status|backup}"
            return 1
    end
end

function __homekase_create_app -a app_name
    # Validate app name: lowercase letters, numbers, hyphens only
    if not string match -qr '^[a-z0-9][a-z0-9-]*$' "$app_name"
        echo "✗ Invalid app name: '$app_name'"
        echo "  Must contain only lowercase letters, numbers, and hyphens."
        echo "  Must start with a letter or number."
        return 1
    end

    set -l APP_DIR "$HOMELAB_DIR/apps/$app_name"

    if test -d "$APP_DIR"
        echo "! App '$app_name' already exists at $APP_DIR"
        read -p "Overwrite? [y/N] " -l confirm
        if not string match -q "y" "$confirm"
            return
        end
    end

    echo ":: Scaffolding $app_name..."

    mkdir -p "$APP_DIR"/{api,frontend,.github/workflows}

    set -l db_password (openssl rand -base64 24)
    set -l repo_url ""

    read -p "GitHub repo URL (for runner, optional): " -l repo_url
    set -l runner_token ""
    if test -n "$repo_url"
        read -p "GitHub runner token: " -l runner_token -s
        echo
    end

    set -l template_dir /opt/homelab/templates/app

    # Copy and render templates
    for file in docker-compose.yml api/Dockerfile api/package.json api/index.js frontend/Dockerfile frontend/nginx.conf frontend/index.html
        set -f src "$template_dir/$file"
        set -f dst "$APP_DIR/$file"

        if test -f "$src"
            sed "s/{{APP_NAME}}/$app_name/g" "$src" > "$dst"
            echo "  ✓ $file"
        end
    end

    # Copy GitHub Actions workflow
    set -f workflow_src "$template_dir/.github/workflows/deploy.yml"
    set -f workflow_dst "$APP_DIR/.github/workflows/deploy.yml"
    if test -f "$workflow_src"
        sed "s/{{APP_NAME}}/$app_name/g" "$workflow_src" > "$workflow_dst"
        echo "  ✓ .github/workflows/deploy.yml"
    end

    # Create .env
    echo "DB_PASSWORD=$db_password" > "$APP_DIR/.env"
    echo "  ✓ .env"

    # Create development .gitignore
    echo ".env" > "$APP_DIR/.gitignore"
    echo "node_modules/" >> "$APP_DIR/.gitignore"
    echo "  ✓ .gitignore"

    # Set up GitHub runner if repo URL provided
    if test -n "$repo_url" -a -n "$runner_token"
        set -l runner_dir "$HOMELAB_DIR/github-runner"
        mkdir -p "$runner_dir"

        # Write secrets to .env (not in compose)
        echo "REPO_URL=$repo_url" > "$runner_dir/.env.$app_name"
        echo "RUNNER_TOKEN=$runner_token" >> "$runner_dir/.env.$app_name"

        set -l runner_compose "$runner_dir/docker-compose.yml"
        set -l runner_name "$app_name-runner"

        if not test -f "$runner_compose"
            echo "services:" > "$runner_compose"
        end

        echo "" >> "$runner_compose"
        echo "  $runner_name:" >> "$runner_compose"
        echo "    image: myoung34/github-runner:latest" >> "$runner_compose"
        echo "    container_name: $runner_name" >> "$runner_compose"
        echo "    restart: unless-stopped" >> "$runner_compose"
        echo "    env_file:" >> "$runner_compose"
        echo "      - .env.$app_name" >> "$runner_compose"
        echo "    environment:" >> "$runner_compose"
        echo "      - RUNNER_LABELS=homelab" >> "$runner_compose"
        # WARNING: Docker socket grants container full root access to host
        echo "    volumes:" >> "$runner_compose"
        echo "      - /var/run/docker.sock:/var/run/docker.sock" >> "$runner_compose"
        echo "    networks:" >> "$runner_compose"
        echo "      - traefik-net" >> "$runner_compose"

        docker compose -f "$runner_compose" up -d $runner_name 2>/dev/null
        echo "  ✓ GitHub runner registered"
        echo "  ✓ Runner credentials saved to $runner_dir/.env.$app_name"
    end

    # Start the app
    cd "$APP_DIR"
    docker compose up -d
    cd -

    echo ""
    echo "━━━ $app_name deployed ━━━"
    echo "  http://$app_name.home"
    echo "  DB password saved to $APP_DIR/.env"
    echo ""

    # Add to URLs file
    if test -f "$URLS_FILE"
        if not grep -q "$app_name.home" "$URLS_FILE"
            echo "$app_name      → http://$app_name.home" >> "$URLS_FILE"
        end
    end
end

function __homekase_update
    echo "━━━ homekase update ━━━"
    echo ""

    # 1. System packages
    echo "── Updating system packages ──"
    sudo apt update -qq
    sudo apt upgrade -y -qq
    echo ""

    # 2. Clone latest repo to get fresh functions and libs
    if not command -v git >/dev/null 2>&1
        echo "! git is required. Install it first."
        return 1
    end

    set -l tmp_dir (mktemp -d)
    git clone --depth=1 "$REPO_URL" "$tmp_dir" 2>/dev/null
    or begin
        echo "! Failed to clone repository"
        return 1
    end

    # 3. Update curl-installed tools (force latest)
    if test -x "$tmp_dir/lib/tools.sh"
        echo "── Updating terminal tools ──"

        # zellij
        set -l ZELLIJ_VERSION (curl -s "https://api.github.com/repos/zellij-org/zellij/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        if test -n "$ZELLIJ_VERSION"
            curl -fsSL "https://github.com/zellij-org/zellij/releases/download/v$ZELLIJ_VERSION/zellij-x86_64-unknown-linux-musl.tar.gz" -o /tmp/zellij.tar.gz
            and sudo tar xzf /tmp/zellij.tar.gz -C /tmp
            and sudo mv /tmp/zellij /usr/local/bin/zellij
            and echo "  ✓ zellij $ZELLIJ_VERSION"
        end

        # lazygit
        set -l LAZYGIT_VERSION (curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        if test -n "$LAZYGIT_VERSION"
            curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v$LAZYGIT_VERSION/lazygit_$LAZYGIT_VERSION"_Linux_x86_64.tar.gz -o /tmp/lazygit.tar.gz
            and sudo tar xzf /tmp/lazygit.tar.gz -C /tmp
            and sudo mv /tmp/lazygit /usr/local/bin/lazygit
            and echo "  ✓ lazygit $LAZYGIT_VERSION"
        end

        # lazydocker
        curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | sudo bash
        and echo "  ✓ lazydocker updated"

        # yazi
        set -l YAZI_VERSION (curl -s "https://api.github.com/repos/sxyazi/yazi/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        if test -n "$YAZI_VERSION"
            curl -fsSL "https://github.com/sxyazi/yazi/releases/download/v$YAZI_VERSION/yazi-x86_64-unknown-linux-gnu.zip" -o /tmp/yazi.zip
            and sudo unzip -q -o /tmp/yazi.zip -d /tmp
            and sudo mv "/tmp/yazi-x86_64-unknown-linux-gnu/yazi" /usr/local/bin/yazi
            and echo "  ✓ yazi $YAZI_VERSION"
        end

        # neovim
        sudo curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" -o /tmp/nvim.tar.gz
        and sudo rm -rf /opt/nvim-linux-x86_64
        and sudo tar xzf /tmp/nvim.tar.gz -C /opt
        and sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
        and echo "  ✓ neovim updated"

        # starship
        curl -fsSL https://starship.rs/install.sh | sudo sh -s -- -y
        and echo "  ✓ starship updated"
    end

    # 4. Update homekase fish function from repo
    echo "── Updating homekase CLI ──"
    set -l func_dir ~/.config/fish/functions
    mkdir -p "$func_dir"
    cp "$tmp_dir/functions/homekase.fish" "$func_dir/homekase.fish"
    and echo "  ✓ homekase.fish updated"

    # 5. Docker images — pull latest for all compose stacks
    echo "── Updating Docker services ──"
    for compose_file in (find /opt/homelab -name docker-compose.yml -maxdepth 2 2>/dev/null)
        set -l dir (dirname "$compose_file")
        echo "  Pulling images in $dir..."
        docker compose -f "$compose_file" pull --quiet 2>/dev/null
        docker compose -f "$compose_file" up -d 2>/dev/null
    end

    # 6. Assistant — git pull + rebuild
    if test -d /opt/homelab/assistant
        echo ""
        echo "── Updating AI Assistant ──"
        git -C /opt/homelab/assistant pull --quiet
        docker compose -f /opt/homelab/assistant/docker-compose.yml build --quiet
        docker compose -f /opt/homelab/assistant/docker-compose.yml up -d
    end

    # 7. Clean up old Docker images
    docker image prune -f 2>/dev/null

    # 8. Clean up temp files
    rm -rf "$tmp_dir"

    echo ""
    echo "✓ homekase is up to date"
end

function __homekase_status
    echo "━━━ homekase status ━━━"
    echo ""

    # System resources
    echo "── System ──"
    set -l mem_total (free -h | awk '/Mem:/{print $2}')
    set -l mem_used (free -h | awk '/Mem:/{print $3}')
    set -l cpu_load (uptime | awk -F'load average:' '{print $2}' | xargs)
    echo "  RAM:   $mem_used / $mem_total"
    echo "  Load:  $cpu_load"
    echo ""

    # Disk usage
    echo "── Storage ──"
    if mountpoint -q /data 2>/dev/null
        df -h /data | tail -1 | awk '{print "  /data:    " $3 " / " $2 " (" $5 ")"}'
    else if test -d /data
        echo "  /data:    (subdirectory on root)"
    else
        echo "  /data:    not configured"
    end
    if mountpoint -q /storage 2>/dev/null
        df -h /storage | tail -1 | awk '{print "  /storage: " $3 " / " $2 " (" $5 ")"}'
    else if test -d /storage
        echo "  /storage: (subdirectory on root)"
    else
        echo "  /storage: not configured"
    end
    if mountpoint -q /backups 2>/dev/null
        df -h /backups | tail -1 | awk '{print "  /backups: " $3 " / " $2 " (" $5 ")"}'
    else if test -d /backups
        echo "  /backups: (subdirectory on root)"
    else
        echo "  /backups: not configured"
    end
    echo ""

    # Running services
    echo "── Services ──"
    if test -f "$URLS_FILE"
        cat "$URLS_FILE"
    else
        echo "  No services recorded"
    end
    echo ""

    # Docker compose stacks
    echo "── Docker Stacks ──"
    if command -v docker >/dev/null 2>&1
        docker compose ls --format "table {{.Name}}\t{{.Status}}" 2>/dev/null
    else
        echo "  Docker not installed"
    end
    echo ""

    # Custom apps
    if test -d "$HOMELAB_DIR/apps"
        set -l apps (ls "$HOMELAB_DIR/apps/" 2>/dev/null)
        if test -n "$apps"
            echo "── Custom Apps ──"
            for app in $apps
                echo "  $app → http://$app.home"
            end
        end
    end
end
