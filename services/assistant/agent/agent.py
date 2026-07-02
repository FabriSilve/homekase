import json
import logging
from datetime import datetime
from typing import Any

import httpx

import tools  # noqa: F401
from tool_registry import registry

logger = logging.getLogger(__name__)

_MAX_TOOL_ROUNDS = 5


def _build_system_prompt() -> str:
    today = datetime.now().strftime("%A, %B %d, %Y")
    return (
        f"You are Aria, a helpful AI assistant for a homelab. Today is {today}.\n"
        "You have access to tools for:\n"
        "- Fetching news headlines from RSS feeds\n"
        "- Checking system status and running containers\n"
        "- Getting weather information\n"
        "- Fetching and reading web page content from URLs\n"
        "- Searching the web\n\n"
        "Use tools when the user's request matches their capabilities. "
        "Be concise and helpful. Chain multiple tool calls if needed to fully answer the request. "
        "When you use a tool, wait for the result before responding."
    )


async def _call_ollama(
    messages: list[dict[str, Any]],
    config: dict[str, Any],
    tools_list: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    url = config["ollama_url"] + "/api/chat"
    payload: dict[str, Any] = {
        "model": config["model"],
        "messages": messages,
        "stream": False,
        "options": {},
    }
    if num_ctx := config.get("num_ctx"):
        payload["options"]["num_ctx"] = num_ctx
    if tools_list:
        payload["tools"] = tools_list

    async with httpx.AsyncClient(timeout=None) as client:
        resp = await client.post(url, json=payload)
        resp.raise_for_status()
        return resp.json()


async def _execute_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    result = registry.execute(name, arguments)
    if hasattr(result, "__await__"):
        return await result
    return result


async def process_chat(
    text: str,
    config: dict[str, Any] | None = None,
    prior_messages: list[dict[str, Any]] | None = None,
) -> str:
    if config is None:
        config = {}

    messages: list[dict[str, Any]] = [{"role": "system", "content": _build_system_prompt()}]
    if prior_messages:
        messages.extend(prior_messages)
    messages.append({"role": "user", "content": text})

    tool_definitions = registry.get_definitions()
    response_data = await _call_ollama(messages, config, tools_list=tool_definitions)
    message = response_data["message"]

    for _ in range(_MAX_TOOL_ROUNDS):
        tool_calls = message.get("tool_calls")
        if not tool_calls:
            break
        messages.append(message)

        for call in tool_calls:
            func = call["function"]
            logger.info("Executing tool: %s", func["name"])
            try:
                tool_result = await _execute_tool(func["name"], func.get("arguments", {}))
            except Exception as exc:
                logger.exception("Tool %s failed", func["name"])
                tool_result = {"text_data": f"Tool '{func['name']}' failed: {exc}"}

            messages.append({
                "role": "tool",
                "content": json.dumps(tool_result.get("text_data", tool_result)),
            })

        response_data = await _call_ollama(messages, config)
        message = response_data["message"]

    return message.get("content") or "I couldn't generate a response."
