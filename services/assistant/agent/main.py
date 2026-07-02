import json
import logging
import os
from collections.abc import AsyncGenerator
from typing import Any

import yaml
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

import tools  # noqa: F401
from agent import process_chat

logger = logging.getLogger(__name__)

app = FastAPI(title="Homekase Assistant Agent")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def load_config() -> dict[str, Any]:
    config_path = os.path.join(os.path.dirname(__file__), "config.yml")
    with open(config_path) as f:
        config: dict[str, Any] = yaml.safe_load(f)
    if model := os.environ.get("OLLAMA_MODEL"):
        config["model"] = model
    if url := os.environ.get("OLLAMA_URL"):
        config["ollama_url"] = url
    if url := os.environ.get("SEARXNG_URL"):
        config["searxng_url"] = url
    return config


config = load_config()


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    model: str | None = None
    messages: list[ChatMessage]
    stream: bool = True


def _extract_user_message(messages: list[ChatMessage]) -> str:
    for msg in reversed(messages):
        if msg.role == "user":
            return msg.content
    return messages[-1].content if messages else ""


def _build_prior_messages(messages: list[ChatMessage]) -> list[dict[str, str]]:
    prior = []
    for msg in messages[:-1]:
        if msg.role in ("user", "assistant"):
            prior.append({"role": msg.role, "content": msg.content})
    return prior


def _sse_chunk(content: str, finish_reason: str | None = None) -> str:
    delta = {"content": content} if content else {}
    if finish_reason:
        delta["finish_reason"] = finish_reason
    data = {
        "id": "chatcmpl-1",
        "object": "chat.completion.chunk",
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish_reason}],
    }
    return f"data: {json.dumps(data)}\n\n"


async def _stream_chat(request: ChatRequest) -> AsyncGenerator[str]:
    user_text = _extract_user_message(request.messages)
    prior = _build_prior_messages(request.messages)

    yield _sse_chunk("", None)

    response_text = ""
    try:
        response_text = await process_chat(user_text, config, prior_messages=prior or None)
    except Exception as e:
        logger.exception("Chat processing failed")
        response_text = f"Error: {e}"

    if response_text:
        yield _sse_chunk(response_text, None)

    yield _sse_chunk("", "stop")
    yield "data: [DONE]\n\n"


@app.post("/v1/chat/completions")
async def chat_completions(request: ChatRequest):
    if request.stream:
        return StreamingResponse(
            _stream_chat(request),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )

    user_text = _extract_user_message(request.messages)
    prior = _build_prior_messages(request.messages)
    try:
        response_text = await process_chat(user_text, config, prior_messages=prior or None)
    except Exception as e:
        logger.exception("Chat processing failed")
        response_text = f"Error: {e}"

    return {
        "id": "chatcmpl-1",
        "object": "chat.completion",
        "choices": [{"index": 0, "message": {"role": "assistant", "content": response_text}, "finish_reason": "stop"}],
    }


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{"id": config.get("model", "qwen2.5:3b"), "object": "model"}],
    }


@app.get("/api/health")
async def health():
    return {"status": "ok"}
