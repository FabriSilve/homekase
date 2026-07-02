from typing import Any

import httpx
import trafilatura

from tool_registry import registry


@registry.register(
    name="fetch_url",
    description="Fetch the content of a URL and return it as plain text. Use when user asks to read, summarize, or get information from a web link.",
    parameters={
        "url": {"type": "string", "description": "The URL to fetch"},
    },
)
async def fetch_url(url: str) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            resp = await client.get(url, headers={"User-Agent": "HomekaseAssistant/1.0"})
            resp.raise_for_status()
            html = resp.text

        text = trafilatura.extract(html, include_comments=False, include_tables=False)
        if not text:
            return {"text_data": f"The page at {url} returned no extractable text content."}

        if len(text) > 30000:
            text = text[:30000] + "\n\n[Content truncated at 30000 characters]"

        return {"text_data": f"Content from {url}:\n\n{text}"}

    except httpx.HTTPStatusError as e:
        return {"text_data": f"Failed to fetch {url}: HTTP {e.response.status_code}"}
    except httpx.RequestError as e:
        return {"text_data": f"Failed to fetch {url}: {e}"}
    except Exception as e:
        return {"text_data": f"Failed to process {url}: {e}"}
