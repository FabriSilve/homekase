import os
from typing import Any

import httpx

from tool_registry import registry

FABRIC_URL = "http://fabric:8080"


def _fabric_call(pattern: str, input_text: str) -> str:
    fabric_url = os.environ.get("FABRIC_URL", FABRIC_URL)
    resp = httpx.post(
        f"{fabric_url}/chat",
        json={"input": input_text, "pattern": pattern, "stream": False},
        timeout=120.0,
    )
    resp.raise_for_status()
    return str(resp.json().get("content", ""))


@registry.register(
    name="summarize_url",
    description="Fetch and summarize the content of a URL. Use when user asks to read, summarize, or get info from a web link.",
    parameters={
        "url": {"type": "string", "description": "The URL to fetch and summarize"},
    },
)
def summarize_url(url: str) -> dict[str, Any]:
    try:
        result = _fabric_call("summarize", url)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not summarize URL: {e}"}


@registry.register(
    name="summarize",
    description="Summarize any text content. Use for pasted articles, notes, or long text.",
    parameters={
        "content": {"type": "string", "description": "Text to summarize"},
    },
)
def summarize(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("summarize", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not summarize: {e}"}


@registry.register(
    name="extract_wisdom",
    description="Extract key ideas, quotes, and insights from text or a URL. More thorough than summarize.",
    parameters={
        "content": {"type": "string", "description": "Text content or URL to analyze"},
    },
)
def extract_wisdom(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("extract_wisdom", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not extract wisdom: {e}"}


@registry.register(
    name="extract_article_wisdom",
    description="Deep extraction of insights, ideas, and lessons from an article or essay.",
    parameters={
        "content": {"type": "string", "description": "Article text or URL"},
    },
)
def extract_article_wisdom(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("extract_article_wisdom", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not extract article wisdom: {e}"}


@registry.register(
    name="extract_insights",
    description="Extract the key insights from any content.",
    parameters={
        "content": {"type": "string", "description": "Text to extract insights from"},
    },
)
def extract_insights(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("extract_insights", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not extract insights: {e}"}


@registry.register(
    name="extract_recommendations",
    description="Extract concrete recommendations and action items from content.",
    parameters={
        "content": {"type": "string", "description": "Text to extract recommendations from"},
    },
)
def extract_recommendations(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("extract_recommendations", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not extract recommendations: {e}"}


@registry.register(
    name="extract_ideas",
    description="Extract and list the ideas present in a piece of content.",
    parameters={
        "content": {"type": "string", "description": "Text to extract ideas from"},
    },
)
def extract_ideas(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("extract_ideas", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not extract ideas: {e}"}


@registry.register(
    name="create_summary",
    description="Create a structured summary with sections (one-sentence, short, long). More formatted than summarize.",
    parameters={
        "content": {"type": "string", "description": "Text to create a summary for"},
    },
)
def create_summary(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("create_summary", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not create summary: {e}"}


@registry.register(
    name="explain_code",
    description="Explain what a piece of code does in plain language.",
    parameters={
        "code": {"type": "string", "description": "The code to explain"},
    },
)
def explain_code(code: str) -> dict[str, Any]:
    try:
        result = _fabric_call("explain_code", code)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not explain code: {e}"}


@registry.register(
    name="review_code",
    description="Review code for bugs, security issues, and improvements.",
    parameters={
        "code": {"type": "string", "description": "The code to review"},
    },
)
def review_code(code: str) -> dict[str, Any]:
    try:
        result = _fabric_call("review_code", code)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not review code: {e}"}


@registry.register(
    name="analyze_logs",
    description="Analyze log output to identify errors, patterns, and root causes. Use when user pastes logs or error output.",
    parameters={
        "logs": {"type": "string", "description": "The log content to analyze"},
    },
)
def analyze_logs(logs: str) -> dict[str, Any]:
    try:
        result = _fabric_call("analyze_logs", logs)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not analyze logs: {e}"}


@registry.register(
    name="improve_writing",
    description="Rewrite and improve the quality of a piece of text.",
    parameters={
        "text": {"type": "string", "description": "The text to improve"},
    },
)
def improve_writing(text: str) -> dict[str, Any]:
    try:
        result = _fabric_call("improve_writing", text)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not improve writing: {e}"}


@registry.register(
    name="translate",
    description="Translate text to a target language.",
    parameters={
        "text": {"type": "string", "description": "The text to translate"},
        "language": {"type": "string", "description": "Target language (e.g. Italian, French)"},
    },
)
def translate(text: str, language: str) -> dict[str, Any]:
    try:
        result = _fabric_call("translate", f"Translate to {language}:\n\n{text}")
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not translate: {e}"}


@registry.register(
    name="find_logical_fallacies",
    description="Identify logical fallacies and weak reasoning in an argument or text.",
    parameters={
        "content": {"type": "string", "description": "The argument or text to analyze"},
    },
)
def find_logical_fallacies(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("find_logical_fallacies", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not find logical fallacies: {e}"}


@registry.register(
    name="find_blindspots",
    description="Identify blindspots and gaps in thinking about a topic, plan, or argument.",
    parameters={
        "content": {"type": "string", "description": "The thinking or plan to analyze"},
    },
)
def find_blindspots(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("t_find_blindspots", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not find blindspots: {e}"}


@registry.register(
    name="red_team_thinking",
    description="Steelman and challenge a plan or idea from an adversarial perspective. Use when user wants their thinking stress-tested.",
    parameters={
        "content": {"type": "string", "description": "The plan or idea to red-team"},
    },
)
def red_team_thinking(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("t_red_team_thinking", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not red-team: {e}"}


@registry.register(
    name="give_encouragement",
    description="Provide thoughtful encouragement and perspective on a challenge or situation.",
    parameters={
        "content": {"type": "string", "description": "The situation to respond to"},
    },
)
def give_encouragement(content: str) -> dict[str, Any]:
    try:
        result = _fabric_call("t_give_encouragement", content)
        return {"text_data": result}
    except Exception as e:
        return {"text_data": f"Could not give encouragement: {e}"}
