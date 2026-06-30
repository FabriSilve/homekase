from collections.abc import Callable
from typing import Any


class ToolRegistry:
    def __init__(self) -> None:
        self._tools: dict[str, dict[str, Any]] = {}

    def register(
        self,
        name: str,
        description: str,
        parameters: dict[str, Any],
    ) -> Callable[..., Any]:
        def decorator(func: Callable[..., Any]) -> Callable[..., Any]:
            self._tools[name] = {
                "function": func,
                "definition": {
                    "type": "function",
                    "function": {
                        "name": name,
                        "description": description,
                        "parameters": {
                            "type": "object",
                            "properties": parameters,
                        },
                    },
                },
            }
            return func

        return decorator

    def get_definitions(self) -> list[dict[str, Any]]:
        return [tool["definition"] for tool in self._tools.values()]

    def execute(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if name not in self._tools:
            return {"error": f"Unknown tool: {name}"}
        func = self._tools[name]["function"]
        return func(**arguments)


registry = ToolRegistry()
