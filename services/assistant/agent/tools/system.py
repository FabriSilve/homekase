import platform
import shutil
from typing import Any

from tool_registry import registry


@registry.register(
    name="system_status",
    description="Get basic system status including hostname, OS, and disk usage",
    parameters={},
)
def system_status_tool() -> dict[str, Any]:
    disk = shutil.disk_usage("/")
    disk_used_gb = disk.used / (1024**3)
    disk_total_gb = disk.total / (1024**3)

    info = (
        f"Host: {platform.node()}\n"
        f"OS: {platform.system()} {platform.release()}\n"
        f"Disk: {disk_used_gb:.1f}GB / {disk_total_gb:.1f}GB"
    )

    return {"text_data": info}
