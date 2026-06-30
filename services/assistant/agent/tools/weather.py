from datetime import datetime
from typing import Any

import httpx

from tool_registry import registry

GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

WMO_DESCRIPTIONS: dict[int, str] = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Foggy",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    61: "Light rain",
    63: "Moderate rain",
    65: "Heavy rain",
    71: "Light snow",
    73: "Moderate snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Light showers",
    81: "Moderate showers",
    82: "Violent showers",
    85: "Light snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm with light hail",
    99: "Thunderstorm with heavy hail",
}


def _wmo_to_text(code: int) -> str:
    return WMO_DESCRIPTIONS.get(code, f"Unknown ({code})")


def _day_label(date_str: str, index: int) -> str:
    if index == 0:
        return "Today"
    if index == 1:
        return "Tomorrow"
    try:
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        return dt.strftime("%A")
    except ValueError:
        return date_str


async def fetch_weather(city: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=10.0) as client:
        geo_resp = await client.get(GEOCODING_URL, params={"name": city, "count": 1})
        geo_resp.raise_for_status()
        geo_data = geo_resp.json()

        results = geo_data.get("results")
        if not results:
            return {"text_data": f"City not found: {city}"}

        lat = results[0]["latitude"]
        lon = results[0]["longitude"]
        resolved_name = results[0].get("name", city)

        forecast_resp = await client.get(
            FORECAST_URL,
            params={
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,weather_code,wind_speed_10m",
                "daily": "weather_code,temperature_2m_max,temperature_2m_min",
                "timezone": "auto",
                "forecast_days": 3,
            },
        )
        forecast_resp.raise_for_status()
        data = forecast_resp.json()

    current = data["current"]
    daily = data["daily"]

    temp = current["temperature_2m"]
    condition = _wmo_to_text(current["weather_code"])
    wind = current["wind_speed_10m"]

    forecast = []
    for i, day in enumerate(daily["time"]):
        forecast.append(
            {
                "day": _day_label(day, i),
                "high": daily["temperature_2m_max"][i],
                "low": daily["temperature_2m_min"][i],
                "description": _wmo_to_text(daily["weather_code"][i]),
            }
        )

    text_parts = [f"{resolved_name}: {temp:.0f}°C, {condition}. Wind: {wind:.0f} km/h."]
    for f in forecast:
        text_parts.append(f"{f['day']}: {f['high']:.0f}°C/{f['low']:.0f}°C, {f['description']}.")

    return {"text_data": " ".join(text_parts)}


@registry.register(
    name="get_weather",
    description="Get current weather and forecast for a city",
    parameters={
        "city": {
            "type": "string",
            "description": "City name (optional, uses configured default if omitted)",
        },
    },
)
async def get_weather_tool(city: str | None = None) -> dict[str, Any]:
    from pathlib import Path

    import yaml

    if not city:
        config_path = Path(__file__).parent.parent / "config.yml"
        with open(config_path) as f:
            cfg = yaml.safe_load(f)
        city = cfg.get("weather", {}).get("city", "London")
    return await fetch_weather(city)
