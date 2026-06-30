import asyncio
import os
from typing import Any

import httpx
import yaml
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from jinja2 import Environment, FileSystemLoader

app = FastAPI(title="Homekase App")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_jinja_env = Environment(loader=FileSystemLoader("templates"), auto_reload=False)

HOMEKASE_CONFIG = os.environ.get("HOMEKASE_CONFIG", "/etc/homekase/homekase.yml")
DOCKER_SOCKET = os.environ.get("DOCKER_SOCKET_PATH", "/var/run/docker.sock")


def _load_config() -> dict[str, Any]:
    try:
        with open(HOMEKASE_CONFIG) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def _get_tailscale_info() -> dict[str, str]:
    cfg = _load_config()
    ts = cfg.get("tailscale", {})
    return {
        "hostname": ts.get("hostname", ""),
        "domain": ts.get("domain", ""),
    }


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
async def dashboard():
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
    )
    return HTMLResponse(html)


@app.post("/api/exec", response_class=HTMLResponse)
async def exec_command(request: Request):
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

    try:
        process = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            shell=True,
            executable="/bin/bash",
        )
        stdout, _ = await process.communicate()
        output = stdout.decode("utf-8", errors="replace") if stdout else ""
        exit_code = process.returncode or 0
        html = f"<pre>$ {command}\n{output}\n═══ Process exited with code {exit_code} ═══</pre>"
        return HTMLResponse(html)
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
