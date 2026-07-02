import json
import logging
from collections.abc import AsyncGenerator
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


def _build_payload(
    messages: list[dict[str, Any]],
    config: dict[str, Any],
    stream: bool = False,
    tools_list: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": config["model"],
        "messages": messages,
        "stream": stream,
        "options": {},
    }
    if num_ctx := config.get("num_ctx"):
        payload["options"]["num_ctx"] = num_ctx
    if tools_list:
        payload["tools"] = tools_list
    return payload


async def _call_ollama(
    messages: list[dict[str, Any]],
    config: dict[str, Any],
    tools_list: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    url = config["ollama_url"] + "/api/chat"
    payload = _build_payload(messages, config, stream=False, tools_list=tools_list)

    async with httpx.AsyncClient(timeout=None) as client:
        resp = await client.post(url, json=payload)
        resp.raise_for_status()
        return resp.json()


async def _call_ollama_stream(
    messages: list[dict[str, Any]],
    config: dict[str, Any],
) -> AsyncGenerator[str]:
    url = config["ollama_url"] + "/api/chat"
    payload = _build_payload(messages, config, stream=True)

    async with httpx.AsyncClient(timeout=None) as client:
        async with client.stream("POST", url, json=payload) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                data = json.loads(line)
                if content := data.get("message", {}).get("content"):
                    yield content


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
                "content": str(tool_result.get("text_data", json.dumps(tool_result))),
            })

        response_data = await _call_ollama(messages, config)
        message = response_data["message"]

    return message.get("content") or "I couldn't generate a response."


async def process_chat_stream(
    text: str,
    config: dict[str, Any] | None = None,
    prior_messages: list[dict[str, Any]] | None = None,
) -> AsyncGenerator[str]:
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
                "content": str(tool_result.get("text_data", json.dumps(tool_result))),
            })

        response_data = await _call_ollama(messages, config)
        message = response_data["message"]

    if message.get("tool_calls"):
        yield "Tool call limit reached. Please rephrase your request."
        return

    async for token in _call_ollama_stream(messages, config):
        yield token
