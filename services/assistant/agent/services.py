import os
import subprocess
from typing import Any

import httpx

DOCKER_SOCKET = os.environ.get("DOCKER_SOCKET_PATH", "/var/run/docker.sock")


def _detect_server_ips() -> dict[str, str | None]:
    lan = os.environ.get("SERVER_LAN_IP")
    tailscale = os.environ.get("SERVER_TAILSCALE_IP")

    if lan and tailscale:
        return {"lan": lan, "tailscale": tailscale}

    try:
        result = subprocess.run(["hostname", "-I"], capture_output=True, text=True, timeout=3)
        if result.returncode == 0:
            ips = result.stdout.strip().split()
            for ip in ips:
                ip = ip.strip()
                if ip.startswith("100.") and not tailscale:
                    tailscale = ip
                elif (
                    ip.startswith("192.168.")
                    or ip.startswith("10.")
                    or (ip.startswith("172.") and 16 <= int(ip.split(".")[1]) <= 31)
                ) and not lan:
                    lan = ip
    except Exception:
        pass

    return {"lan": lan, "tailscale": tailscale}


async def get_services() -> dict[str, Any]:
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
        return {"services": [], "server_ips": _detect_server_ips()}

    services: list[dict[str, Any]] = []
    for c in containers:
        labels = c.get("Labels", {}) or {}
        container_name = c.get("Names", [None])[0]
        if container_name:
            container_name = container_name.lstrip("/")

        svc_name = labels.get("com.homekase.service", container_name)
        port = labels.get("com.homekase.port", "")
        tailscale = labels.get("com.homekase.tailscale", "false")

        services.append(
            {
                "name": svc_name,
                "container": container_name,
                "port": port,
                "tailscale": tailscale == "true",
                "status": c.get("State", "unknown"),
            }
        )

    services.sort(key=lambda s: s["name"].lower())
    return {"services": services, "server_ips": _detect_server_ips()}
