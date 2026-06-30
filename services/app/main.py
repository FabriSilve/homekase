import asyncio
import hmac
import hashlib
import os
import secrets
import subprocess
from typing import Any

import httpx
import yaml
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from jinja2 import Environment, FileSystemLoader

app = FastAPI(title="Homekase App")

app.mount("/static", StaticFiles(directory="static"), name="static")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_jinja_env = Environment(loader=FileSystemLoader("templates"), auto_reload=False)

HOMEKASE_CONFIG = os.environ.get("HOMEKASE_CONFIG", "/etc/homekase/homekase.yml")
DOCKER_SOCKET = os.environ.get("DOCKER_SOCKET_PATH", "/var/run/docker.sock")
DASHBOARD_PASSWORD = os.environ.get("DASHBOARD_PASSWORD", "")

_server_secret = secrets.token_hex(32)


def _sign_token(token: str) -> str:
    return hmac.new(_server_secret.encode(), token.encode(), hashlib.sha256).hexdigest()


def _make_session_token() -> str:
    token = secrets.token_hex(16)
    sig = _sign_token(token)
    return f"{token}.{sig}"


def _check_session(request: Request) -> bool:
    if not DASHBOARD_PASSWORD:
        return True
    cookie = request.cookies.get("homekase_session", "")
    if "." not in cookie:
        return False
    token, sig = cookie.rsplit(".", 1)
    return hmac.compare_digest(sig, _sign_token(token))


def _load_config() -> dict[str, Any]:
    try:
        with open(HOMEKASE_CONFIG) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def _get_tailscale_info() -> dict[str, str]:
    cfg = _load_config()
    ts = cfg.get("tailscale", {})
    hostname = ts.get("hostname", "")
    domain = ts.get("domain", "")
    if hostname and not hostname.endswith(".ts.net"):
        ts_host = f"{hostname}.{domain}" if domain else hostname
    else:
        ts_host = hostname
    return {"hostname": ts_host, "domain": domain}


async def _get_services() -> list[dict[str, Any]]:
    try:
        transport = httpx.AsyncHTTPTransport(uds=DOCKER_SOCKET)
        async with httpx.AsyncClient(transport=transport, timeout=5.0) as client:
            resp = await client.get(
                "http://localhost/containers/json",
                params={"filters": '{"label":["com.homekase.service"]}'},
            )
            resp.raise_for_status()
            containers = resp.json()
    except Exception:
        return []

    services = []
    for c in containers:
        labels = c.get("Labels", {}) or {}
        container_name = c.get("Names", [None])[0]
        if container_name:
            container_name = container_name.lstrip("/")

        svc_name = labels.get("com.homekase.service", container_name or "unknown")
        port = labels.get("com.homekase.port", "")

        services.append({
            "name": svc_name,
            "container": container_name,
            "status": c.get("State", "unknown"),
            "port": port,
            "image": c.get("Image", ""),
        })

    services.sort(key=lambda s: s["name"].lower())
    return services


def _get_service_url(ts: dict[str, str], port: str) -> str:
    if ts["hostname"] and port:
        return f"https://{ts['hostname']}:{port}"
    if port:
        return f"http://localhost:{port}"
    return "-"


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    ts = _get_tailscale_info()
    containers = await _get_services()
    cfg = _load_config()
    apps = cfg.get("apps", {})

    service_list = []
    for c in containers:
        port = c["port"]
        url = _get_service_url(ts, port) if port else "-"
        service_list.append({
            "name": c["name"],
            "status": c["status"],
            "port": port,
            "url": url,
        })

    template = _jinja_env.get_template("index.html")
    html = template.render(
        services=service_list,
        tailscale=ts,
        installed_apps=list(apps.keys()),
        dashboard_password=bool(DASHBOARD_PASSWORD),
    )
    return HTMLResponse(html)


_DASHBOARD_LOCKED = """\
<div id="dashboard-content" style="text-align:center;padding:3rem 1rem;">
  <p style="color:var(--text-muted);margin-bottom:1rem;">🔒 Enter password to access Quick Actions and Terminal</p>
  <form hx-post="/api/unlock" hx-swap="outerHTML" style="display:flex;gap:0.5rem;justify-content:center;">
    <input type="password" name="password" class="terminal-input"
           placeholder="Dashboard password" style="max-width:240px;">
    <button class="btn" type="submit">Unlock</button>
  </form>
</div>"""

_DASHBOARD_UNLOCKED = """\
<div class="section-title">Quick Actions</div>
<div class="actions">
  <button class="btn"
          hx-post="/api/exec"
          hx-vals='{"command": "uptime"}'
          hx-target="#terminal"
          hx-swap="innerHTML">
    ⚡ Uptime
  </button>
  <button class="btn"
          hx-post="/api/exec"
          hx-vals='{"command": "df -h /"}'
          hx-target="#terminal"
          hx-swap="innerHTML">
    💾 Disk
  </button>
  <button class="btn"
          hx-post="/api/exec"
          hx-vals='{"command": "free -h"}'
          hx-target="#terminal"
          hx-swap="innerHTML">
    🧠 Memory
  </button>
  <button class="btn"
          hx-post="/api/exec"
          hx-vals='{"command": "docker ps"}'
          hx-target="#terminal"
          hx-swap="innerHTML">
    🐳 Docker
  </button>
  <button class="btn btn-danger"
          hx-post="/api/exec"
          hx-vals='{"command": "sudo shutdown -h now"}'
          hx-target="#terminal"
          hx-swap="innerHTML">
    ⏻ Shutdown
  </button>
  <button class="btn btn-danger"
          hx-post="/api/exec"
          hx-vals='{"command": "sudo reboot"}'
          hx-target="#terminal"
          hx-swap="innerHTML">
    🔄 Reboot
  </button>
</div>
<div class="section-title">Terminal</div>
<div class="terminal" id="terminal">
  Type a command below and press Enter.
</div>
<form class="terminal-input-row"
      hx-post="/api/exec"
      hx-target="#terminal"
      hx-swap="innerHTML"
      hx-on::after-request="this.reset()">
  <input type="text" class="terminal-input" name="command"
         placeholder="$ enter command..." autofocus>
</form>"""


@app.get("/api/section/dashboard", response_class=HTMLResponse)
async def section_dashboard(request: Request):
    if _check_session(request):
        return HTMLResponse(_DASHBOARD_UNLOCKED)
    return HTMLResponse(_DASHBOARD_LOCKED)


@app.post("/api/unlock", response_class=HTMLResponse)
async def unlock(request: Request):
    data = await request.form()
    password = data.get("password", "")
    if password != DASHBOARD_PASSWORD:
        return HTMLResponse(
            '<div id="dashboard-content" style="text-align:center;padding:3rem 1rem;">'
            '<p style="color:var(--accent-red);margin-bottom:1rem;">🔒 Wrong password</p>'
            '<form hx-post="/api/unlock" hx-swap="outerHTML" style="display:flex;gap:0.5rem;justify-content:center;">'
            '<input type="password" name="password" class="terminal-input" '
            'placeholder="Dashboard password" style="max-width:240px;">'
            '<button class="btn" type="submit">Unlock</button>'
            "</form></div>"
        )
    token = _make_session_token()
    resp = HTMLResponse("<script>location.reload()</script>")
    resp.set_cookie(
        "homekase_session", token,
        httponly=True, samesite="lax", max_age=86400,
    )
    return resp


@app.post("/api/exec", response_class=HTMLResponse)
async def exec_command(request: Request):
    if not _check_session(request):
        return HTMLResponse("<pre>🔒 Unlock the dashboard first</pre>")

    command = ""
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        body = await request.json()
        command = (body or {}).get("command", "")
    else:
        form = await request.form()
        command = form.get("command", "")

    if not command.strip():
        return HTMLResponse("<pre>No command provided</pre>")

    user = os.environ.get("HOMEKASE_USER", "root")
    cwd = f"/home/{user}" if user != "root" else "/root"

    try:
        result = subprocess.run(
            ["bash", "-c", command],
            capture_output=True, text=True, timeout=30,
            cwd=cwd,
        )
        output = result.stdout + result.stderr
        exit_code = result.returncode
        html = f"<pre>$ {command}\n{output}\n═══ Process exited with code {exit_code} ═══</pre>"
        return HTMLResponse(html)
    except subprocess.TimeoutExpired:
        return HTMLResponse("<pre>Command timed out (30s)</pre>")
    except Exception as e:
        return HTMLResponse(f"<pre>Error: {e}</pre>")


@app.get("/api/services")
async def api_services():
    ts = _get_tailscale_info()
    containers = await _get_services()
    return {"services": containers, "tailscale": ts}


@app.get("/api/health")
async def health():
    return {"status": "ok"}
