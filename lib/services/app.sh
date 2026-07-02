#!/usr/bin/env bash
# Server dashboard service installer.
# Deploys natively on the host (not in Docker) via systemd.

SERVICE_NAME="homekase-app"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

_ensure_venv() {
  local test_dir
  test_dir="$(mktemp -d)"
  if python3 -m venv "${test_dir}" 2>/dev/null; then
    rm -rf "${test_dir}"
    return 0
  fi
  rm -rf "${test_dir}"

  info "python3-venv not available. Installing..."
  local py_ver
  py_ver="$(python3 --version | grep -oP '\d+\.\d+')"

  if command -v apt &>/dev/null; then
    apt install -y "python${py_ver}-venv" 2>/dev/null || {
      apt update -qq 2>/dev/null || true
      apt install -y "python${py_ver}-venv"
    }
  elif command -v dnf &>/dev/null; then
    dnf install -y python3-virtualenv
  elif command -v pacman &>/dev/null; then
    pacman -S --noconfirm python-virtualenv
  else
    error "Could not install python3-venv. Install python3-venv manually and retry."
    exit 1
  fi
}

deploy_app() {
  require_root
  header "Installing Server Dashboard"

  local PORT TS BIND_ADDR APP_URL HOMEKASE_USER DASHBOARD_PASSWORD
  PORT="$(port_wizard "app" 1)"
  TS="$(tailscale_serve_setup "${PORT}")"
  BIND_ADDR="$(bind_address "${TS}")"
  APP_URL="$(service_url "${PORT}")"
  HOMEKASE_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  read -rsp "Dashboard password (enter for no auth): " DASHBOARD_PASSWORD
  echo

  local APP_DIR="${HOMELAB_DIR}/app"
  local SRC_DIR="${HOMEKASE_REPO_DIR}/services/app"
  local VENV_DIR="${APP_DIR}/venv"

  mkdir -p "${APP_DIR}"

  info "Copying source files..."
  cp -r "${SRC_DIR}/main.py" "${SRC_DIR}/pyproject.toml" "${SRC_DIR}/templates" "${SRC_DIR}/static" "${APP_DIR}/"

  _ensure_venv
  info "Creating Python virtual environment..."
  python3 -m venv "${VENV_DIR}"

  info "Installing Python dependencies..."
  "${VENV_DIR}/bin/pip" install --no-cache-dir \
    fastapi uvicorn httpx pyyaml jinja2 python-multipart

  write_env_file "app" "PORT=${PORT}
TS=${TS}
BIND_ADDR=${BIND_ADDR}
APP_URL=${APP_URL}
HOMEKASE_USER=${HOMEKASE_USER}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}
HOMEKASE_CONFIG=/etc/homekase/homekase.yml"

  info "Creating systemd service..."
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Homekase Dashboard
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
ExecStart=${VENV_DIR}/bin/uvicorn main:app --host 127.0.0.1 --port ${PORT}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}"

  config_app_set app installed true
  config_app_set app port      "${PORT}"
  config_app_set app tailscale "${TS}"

  ok "Dashboard running on port ${PORT}  →  ${APP_URL}"
  info "Service: ${SERVICE_NAME}"
}

remove_app() {
  require_root
  header "Removing Server Dashboard"

  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload

  local port
  port="$(config_app_get app port 2>/dev/null || true)"
  [[ -n "${port}" ]] && tailscale_serve_remove "${port}"

  remove_service_dir "app"
  config_app_remove app
  ok "Dashboard removed."
}
