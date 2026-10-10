from dataclasses import dataclass

import httpx


def is_active_flood(event: str) -> bool:
    """A warning or advisory means flooding is occurring or imminent. A watch does not."""
    name = event.casefold()
    if "flood" not in name:
        return False
    if "watch" in name or "outlook" in name or "statement" in name:
        return False
    return True


def classify_alert(event: str) -> tuple[str | None, bool]:
    """Map an NWS event name to hurricane, storm, heavy rain, or flood.

    A watch or outlook stays in the list and is marked as a watch. Products that
    are not one of those four families return no category.
    """
    name = event.casefold()
    is_watch = "watch" in name or "outlook" in name
    if any(token in name for token in ("hurricane", "tropical storm", "tropical depression", "storm surge")):
        return "hurricane", is_watch
    if "flash flood" in name or "heavy rain" in name or "excessive rainfall" in name:
        return "heavy_rain", is_watch
    if "flood" in name:
        return "flood", is_watch
    if any(token in name for token in ("thunderstorm", "tornado", "marine", "high wind", "wind advisory", "gale")):
        return "storm", is_watch
    return None, is_watch


@dataclass
class WeatherAlert:
    event: str
    headline: str
    active_flood: bool
    severity: str = ""
    urgency: str = ""
    instruction: str = ""
    onset: str | None = None
    ends: str | None = None
    category: str | None = None
    is_watch: bool = False


@dataclass
class WeatherReport:
    forecast: str | None
    temperature_f: float | None
    alerts: list[WeatherAlert]

    @property
    def flood_active(self) -> bool:
        return any(alert.active_flood for alert in self.alerts)

    @property
    def headlines(self) -> list[str]:
        return [alert.headline for alert in self.alerts]


def _text(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


# Downtown Miami. The widget and Watch ask about the city, not one trip.
MIAMI_LAT = 25.7617
MIAMI_LNG = -80.1918


class WeatherClient:
    def __init__(self, client: httpx.AsyncClient):
        self.client = client

    async def report(self, lat: float, lng: float) -> WeatherReport:
        alerts = await self._alerts(lat, lng)
        forecast, temperature = await self._forecast(lat, lng)
        return WeatherReport(forecast=forecast, temperature_f=temperature, alerts=alerts)

    async def _alerts(self, lat: float, lng: float) -> list[WeatherAlert]:
        response = await self.client.get(
            "https://api.weather.gov/alerts/active",
            params={"point": f"{lat:.4f},{lng:.4f}"},
            headers={"Accept": "application/geo+json"},
            timeout=15,
        )
        response.raise_for_status()
        alerts: list[WeatherAlert] = []
        for feature in (response.json().get("features") or [])[:12]:
            props = feature.get("properties") or {}
            event = str(props.get("event") or "").strip()
            headline = str(props.get("headline") or event).strip()
            if not headline:
                continue
            category, is_watch = classify_alert(event or headline)
            alerts.append(
                WeatherAlert(
                    event=event or headline,
                    headline=headline,
                    active_flood=is_active_flood(event),
                    severity=str(props.get("severity") or "").strip(),
                    urgency=str(props.get("urgency") or "").strip(),
                    instruction=str(props.get("instruction") or "").strip(),
                    onset=_text(props.get("onset")),
                    ends=_text(props.get("ends")),
                    category=category,
                    is_watch=is_watch,
                )
            )
        return alerts

    async def _forecast(self, lat: float, lng: float) -> tuple[str | None, float | None]:
        points = await self.client.get(
            f"https://api.weather.gov/points/{lat:.4f},{lng:.4f}",
            headers={"Accept": "application/geo+json"},
            timeout=15,
        )
        points.raise_for_status()
        forecast_url = (points.json().get("properties") or {}).get("forecast")
        if not forecast_url:
            return None, None
        forecast = await self.client.get(forecast_url, headers={"Accept": "application/geo+json"}, timeout=15)
        forecast.raise_for_status()
        periods = (forecast.json().get("properties") or {}).get("periods") or []
        if not periods:
            return None, None
        period = periods[0]
        text = period.get("shortForecast")
        temperature = period.get("temperature")
        return (str(text) if text else None, float(temperature) if temperature is not None else None)
