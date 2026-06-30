import os
from typing import Any

import httpx

from tool_registry import registry

SEARXNG_URL = "http://searxng:8888"


@registry.register(
    name="web_search",
    description="Search the web for information. Use when user asks about current events, facts, or anything requiring up-to-date information.",
    parameters={
        "query": {"type": "string", "description": "The search query"},
        "max_results": {"type": "integer", "description": "Maximum number of results (default: 5)"},
    },
)
async def web_search(query: str, max_results: int = 5) -> dict[str, Any]:
    searxng_url = os.environ.get("SEARXNG_URL", SEARXNG_URL)

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(
                f"{searxng_url}/search",
                params={
                    "q": query,
                    "format": "json",
                    "language": "en",
                    "categories": "general",
                    "pageno": 1,
                },
            )
            resp.raise_for_status()
            data = resp.json()

        results = data.get("results", [])[:max_results]

        if not results:
            return {"text_data": f"No search results found for: {query}"}

        text_lines = [f"Search results for '{query}':"]
        for r in results:
            title = r.get("title", "Untitled")
            url = r.get("url", "")
            snippet = r.get("content", "")
            text_lines.append(f"- {title}: {snippet[:200]}")

        return {"text_data": "\n".join(text_lines)}

    except Exception as e:
        return {"text_data": f"Web search failed: {e}"}
