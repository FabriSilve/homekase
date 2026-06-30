from typing import Any

import feedparser

from tool_registry import registry


async def fetch_news(
    sources: list[str],
    topic: str | None = None,
    max_items: int = 10,
) -> dict[str, Any]:
    entries: list[dict[str, str]] = []

    for url in sources:
        feed = feedparser.parse(url)
        for entry in feed.entries[:max_items]:
            title = str(entry.title)
            link = str(entry.link)
            if topic and topic.lower() not in title.lower():
                continue
            entries.append({"title": title, "link": link})

    entries = entries[:max_items]

    if not entries:
        return {"text_data": "No news found."}

    text_lines = [f"- {e['title']}" for e in entries]

    return {
        "text_data": "Here are the latest headlines:\n" + "\n".join(text_lines),
    }


@registry.register(
    name="fetch_news",
    description="Get today's news headlines from configured RSS sources",
    parameters={
        "topic": {"type": "string", "description": "Optional topic to filter headlines by"},
    },
)
async def fetch_news_tool(topic: str | None = None) -> dict[str, Any]:
    from pathlib import Path

    import yaml

    config_path = Path(__file__).parent.parent / "config.yml"
    with open(config_path) as f:
        cfg = yaml.safe_load(f)
    sources: list[str] = cfg.get("news_sources", [])
    return await fetch_news(sources=sources, topic=topic)
