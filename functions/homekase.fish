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

        case ""
            echo "Usage: homekase {create|update|status}"
            echo ""
            echo "  create <name>  Scaffold a new app"
            echo "  update         Re-run setup (idempotent)"
            echo "  status         Show resources, services, and URLs"

        case '*'
            echo "Unknown command: $argv[1]"
            echo "Usage: homekase {create|update|status}"
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
    echo ":: Updating homekase..."

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

    cd "$tmp_dir"
    if test -f "setup.sh"
        sudo bash setup.sh
    end
    cd -
    rm -rf "$tmp_dir"
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
        df -h /data | tail -1 | awk '{print "  /data:   " $3 " / " $2 " (" $5 ")"}'
    else
        echo "  /data:   not mounted"
    end
    if mountpoint -q /storage 2>/dev/null
        df -h /storage | tail -1 | awk '{print "  /storage: " $3 " / " $2 " (" $5 ")"}'
    else
        echo "  /storage: not mounted"
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
