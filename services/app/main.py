import asyncio
import os
from collections.abc import AsyncGenerator
from typing import Any

import httpx
import yaml
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.templating import Jinja2Templates

app = FastAPI(title="Homekase App")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

templates = Jinja2Templates(directory="templates")

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

    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "services": service_list,
            "tailscale": ts,
            "installed_apps": list(apps.keys()),
        },
    )


class ExecResult:
    def __init__(self, command: str):
        self.command = command

    async def stream(self) -> AsyncGenerator[str]:
        yield f"data: $ {self.command}\n\n"
        try:
            process = await asyncio.create_subprocess_shell(
                self.command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                shell=True,
                executable="/bin/bash",
            )
            assert process.stdout is not None
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                decoded = line.decode("utf-8", errors="replace")
                yield f"data: {decoded}\n\n"
            await process.wait()
            exit_code = process.returncode or 0
            yield f"data: \n"
            yield f"data: ═══ Process exited with code {exit_code} ═══\n\n"
        except Exception as e:
            yield f"data: Error: {e}\n\n"


@app.post("/api/exec")
async def exec_command(command: str = ""):
    if not command.strip():
        return StreamingResponse(
            _iter_text("data: No command provided\n\n"),
            media_type="text/event-stream",
        )
    exec_result = ExecResult(command)
    return StreamingResponse(
        exec_result.stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/api/services")
async def api_services():
    ts = _get_tailscale_info()
    containers = await _get_services()
    return {"services": containers, "tailscale": ts}


@app.get("/api/health")
async def health():
    return {"status": "ok"}


async def _iter_text(text: str):
    yield text
