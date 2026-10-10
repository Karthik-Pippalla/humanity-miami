from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import httpx

from app.geo import circle_ring
from app.schemas import Place

EVENT_RADIUS_M = 450
WINDOW_BEFORE = timedelta(minutes=90)
WINDOW_AFTER = timedelta(hours=2)


@dataclass
class LiveEvent:
    id: str
    name: str
    venue: str
    start: datetime | None
    end: datetime | None
    lat: float
    lng: float

    @property
    def ring(self) -> list[list[float]]:
        return circle_ring(self.lng, self.lat, EVENT_RADIUS_M)

    def window(self) -> tuple[datetime, datetime] | None:
        if self.start is None:
            return None
        finish = self.end or (self.start + timedelta(hours=3))
        return self.start - WINDOW_BEFORE, finish + WINDOW_AFTER


class EventClient:
    def __init__(self, client: httpx.AsyncClient, api_key: str):
        self.client = client
        self.api_key = api_key

    async def nearby(self, center: Place, depart: datetime) -> tuple[list[LiveEvent], list[str]]:
        if not self.api_key:
            return [], ["ticketmaster_unconfigured"]
        start = depart.astimezone(timezone.utc) - timedelta(hours=3)
        end = depart.astimezone(timezone.utc) + timedelta(hours=36)
        try:
            response = await self.client.get(
                "https://app.ticketmaster.com/discovery/v2/events.json",
                params={
                    "apikey": self.api_key,
                    "latlong": f"{center.lat},{center.lng}",
                    "radius": "12",
                    "unit": "miles",
                    "size": "15",
                    "sort": "date,asc",
                    "startDateTime": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "endDateTime": end.strftime("%Y-%m-%dT%H:%M:%SZ"),
                },
                timeout=20,
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError):
            return [], ["events_unavailable"]
        events: list[LiveEvent] = []
        for item in (payload.get("_embedded") or {}).get("events") or []:
            venues = (item.get("_embedded") or {}).get("venues") or []
            if not venues:
                continue
            location = venues[0].get("location") or {}
            try:
                lat = float(location["latitude"])
                lng = float(location["longitude"])
            except (KeyError, TypeError, ValueError):
                continue
            dates = (item.get("dates") or {}).get("start") or {}
            event_start = _parse_time(dates.get("dateTime"))
            events.append(
                LiveEvent(
                    id=str(item.get("id") or f"event-{len(events)}"),
                    name=str(item.get("name") or "Scheduled event"),
                    venue=str(venues[0].get("name") or "Venue"),
                    start=event_start,
                    end=None,
                    lat=lat,
                    lng=lng,
                )
            )
        return events, []


def _parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed
