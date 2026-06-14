# Service Installer Patterns

Every service installer under `lib/services/<name>.sh` follows a consistent
set of patterns. Use this as a reference when adding a new service.

## File structure

```
lib/services/
  _common.sh       — shared helpers (do not edit directly)
  service.sh       — dispatcher: list, add, remove, logs
  <name>.sh        — per-service deploy / remove functions
```

## Reference: helpers available in all installers

| Helper | What it does | Returns |
|---|---|---|
| `require_root` | Re-executes via sudo if not root | (exits if can't escalate) |
| `header <text>` | Prints a section header | — |
| `info <msg>` / `ok <msg>` / `warn <msg>` / `error <msg>` | Colored status messages | — |
| `ask_input <prompt> <default>` | Prompt for text input | User's answer |
| `ask_confirm <question>` | Yes / No prompt | true / false |
| `port_wizard <name> <count>` | Ask for port number | Port number |
| `next_available_port` | Suggest next free port from config | Port number |
| `tailscale_serve_setup <port>` | Offer Tailscale Serve exposure | `"true"` or `"false"` |
| `tailscale_serve_remove <port>` | Remove Tailscale Serve on uninstall | — |
| `service_url <port>` | Build external-facing URL | `https://<host>:<port>` or `http://localhost:<port>` |
| `bind_address <ts_flag>` | Docker port bind address | `127.0.0.1:` when TS, empty otherwise |
| `write_service_dir <name>` | Create `/opt/homekase/<name>/` | — |
| `write_compose_file <name> <yaml>` | Write `docker-compose.yml` | — |
| `write_env_file <name> <content>` | Write `.env` for docker-compose | — |
| `start_service <name>` | `docker compose up -d` | — |
| `stop_service <name>` | `docker compose down` | — |
| `remove_service_dir <name>` | Stop + optionally delete data dir | — |
| `config_app_set <name> <key> <val>` | Save metadata in config | — |
| `config_app_remove <name>` | Delete entire app from config | — |
| `config_app_installed <name>` | Check if app is installed | true / false |
| `config_app_get <name> <key>` | Read metadata from config | Value or empty |

## Service deploy function — step by step

Every `deploy_<name>()` follows this order:

```
  1. require_root
  2. header
  3. Collect user input (PORT, DATA_PATH, TS)
  4. Compute derived values (URL, BIND_ADDR)
  5. Write docker-compose.yml and .env
  6. mkdir -p DATA_PATH (with correct ownership)
  7. start_service
  8. config_app_set metadata
  9. ok success message (using URL variable)
```

## Service remove function — step by step

```
  1. require_root
  2. header
  3. Read port from config_app_get
  4. tailscale_serve_remove (if port exists)
  5. remove_service_dir (docker compose down + ask delete)
  6. config_app_remove
  7. ok message
```

## Key rules

### 1. Port mapping must use BIND_ADDR

```yaml
ports:
  - \"\${BIND_ADDR}\${PORT}:<INTERNAL_PORT>\"
```

This binds to `127.0.0.1` when Tailscale is active (avoiding conflict with
tailscaled on the Tailscale interface), and to all interfaces when not.

### 2. Docker-compose variables use `\${VAR}` in bash strings

```bash
write_compose_file "svc" "services:
  svc:
    ports:
      - \"\${BIND_ADDR}\${PORT}:8080\""
```

The `\$` prevents bash from expanding the variable; docker-compose resolves
it from `.env` at runtime.

### 3. .env stores everything docker-compose needs

```bash
write_env_file "svc" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
TS=${TS}
URL=${URL}
BIND_ADDR=${BIND_ADDR}"
```

These `$` are expanded by bash at script time, writing literal values into
the `.env` file.

### 4. Success message uses stored URL variable

```bash
ok "Running on port ${PORT}  →  ${URL}"         # ✅ correct
ok "Running on port ${PORT}  →  http://localhost:${PORT}"  # ❌ hardcoded
```

### 5. Remove function cleans up everything

```bash
remove_<name>() {
  require_root
  local port
  port="$(config_app_get <name> port)"         # read BEFORE config is deleted
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"  # unregister from tailscale
  remove_service_dir "<name>"                  # docker compose down + ask delete
  config_app_remove <name>                     # remove from config
}
```

### 6. Labels on containers

```yaml
labels:
  com.homekase.service: <name>
  com.homekase.port: \"\${PORT}\"
  com.homekase.tailscale: \"\${TS}\"
  com.homekase.backup.type: snapshot|postgres|none
  com.homekase.backup.data: \"\${DATA_PATH}\"
  com.homekase.backup.db-type: sqlite|postgres|none
```

### 7. Register in SERVICES array

Add to `lib/services/service.sh`:

```bash
SERVICES=(
  ...
  "myname:Short description"
)
```

The service file must be at `lib/services/myname.sh` and define
`deploy_myname()` and `remove_myname()`.

### 8. Backup types

- `snapshot` — file-based data in DATA_PATH
- `postgres` — PostgreSQL database (needs db credentials in config)
- `none` — stateless or cache-only service

## Minimal skeleton

```bash
#!/usr/bin/env bash

deploy_<name>() {
  require_root
  header "Installing <Name>"

  local PORT DATA_PATH TS URL BIND_ADDR
  PORT="$(port_wizard "<name>" 1)"
  DATA_PATH="$(ask_input "<Name> data path" "/data/config/<name>")"
  TS="$(tailscale_serve_setup "${PORT}")"
  URL="$(service_url "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"

  write_service_dir "<name>"
  write_compose_file "<name>" "services:
  <name>:
    image: <org>/<image>:latest
    container_name: <name>
    restart: unless-stopped
    ports:
      - \"\${BIND_ADDR}\${PORT}:<INTERNAL_PORT>\"
    volumes:
      - \${DATA_PATH}:/data
    networks:
      - homelab-net
    labels:
      com.homekase.service: <name>
      com.homekase.port: \"\${PORT}\"
      com.homekase.tailscale: \"\${TS}\"
      com.homekase.backup.type: snapshot
      com.homekase.backup.data: \"\${DATA_PATH}\"
      com.homekase.backup.db-type: none

networks:
  homelab-net:
    external: true"

  write_env_file "<name>" "PORT=${PORT}
DATA_PATH=${DATA_PATH}
TS=${TS}
URL=${URL}
BIND_ADDR=${BIND_ADDR}"

  mkdir -p "${DATA_PATH}"
  start_service "<name>"

  config_app_set <name> installed  true
  config_app_set <name> port       "${PORT}"
  config_app_set <name> data_path  "${DATA_PATH}"
  config_app_set <name> tailscale  "${TS}"

  ok "<Name> running on port ${PORT}  →  ${URL}"
}

remove_<name>() {
  require_root
  header "Removing <Name>"
  local port
  port="$(config_app_get <name> port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"
  remove_service_dir "<name>"
  config_app_remove <name>
  ok "<Name> removed."
}
```
