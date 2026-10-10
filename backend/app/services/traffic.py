from dataclasses import dataclass
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import httpx

from app.geo import decode_polyline
from app.schemas import Place
from app.services.valhalla import ValhallaClient, ValhallaError

MIAMI = ZoneInfo("America/New_York")


@dataclass
class TravelLeg:
    duration_seconds: float
    distance_meters: float
    source: str
    coordinates: list[tuple[float, float]]


class TrafficClient:
    """Traffic-aware Google Routes legs, with a Valhalla depart-at fallback."""

    def __init__(self, http: httpx.AsyncClient, api_key: str, valhalla: ValhallaClient):
        self.http = http
        self.api_key = api_key.strip()
        self.valhalla = valhalla
        self.used_fallback = not bool(self.api_key)

    async def leg(self, origin: Place, destination: Place, depart_at: datetime, costing: str = "auto") -> TravelLeg:
        if self.api_key and costing == "auto":
            try:
                return await self._google(origin, destination, depart_at)
            except Exception:
                self.used_fallback = True
        else:
            self.used_fallback = True
        return await self._valhalla(origin, destination, depart_at, costing)

    async def _google(self, origin: Place, destination: Place, depart_at: datetime) -> TravelLeg:
        moment = depart_at if depart_at.tzinfo else depart_at.replace(tzinfo=MIAMI)
        response = await self.http.post(
            "https://routes.googleapis.com/directions/v2:computeRoutes",
            headers={
                "X-Goog-Api-Key": self.api_key,
                "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
            },
            json={
                "origin": {"location": {"latLng": {"latitude": origin.lat, "longitude": origin.lng}}},
                "destination": {"location": {"latLng": {"latitude": destination.lat, "longitude": destination.lng}}},
                "travelMode": "DRIVE",
                "routingPreference": "TRAFFIC_AWARE",
                "departureTime": moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            },
            timeout=12,
        )
        response.raise_for_status()
        routes = response.json().get("routes") or []
        if not routes:
            raise RuntimeError("empty google route")
        route = routes[0]
        encoded = ((route.get("polyline") or {}).get("encodedPolyline")) or ""
        coords = decode_polyline(encoded, 5) if encoded else [(origin.lat, origin.lng), (destination.lat, destination.lng)]
        duration = _seconds(route.get("duration"))
        if duration <= 0:
            raise RuntimeError("google route had no duration")
        return TravelLeg(
            duration_seconds=duration,
            distance_meters=float(route.get("distanceMeters") or 0),
            source="google_traffic",
            coordinates=coords,
        )

    async def _valhalla(self, origin: Place, destination: Place, depart_at: datetime, costing: str) -> TravelLeg:
        try:
            route = await self.valhalla.route(origin, destination, depart_at=depart_at, costing=costing)
        except ValhallaError:
            raise
        coordinates = [(float(lat), float(lng)) for lng, lat in route.line.coords]
        return TravelLeg(
            duration_seconds=route.duration_seconds,
            distance_meters=route.distance_meters,
            source="valhalla_typical",
            coordinates=coordinates,
        )


def _seconds(value) -> float:
    if value is None:
        return 0
    text = str(value).strip()
    if text.endswith("s"):
        text = text[:-1]
    try:
        return float(text)
    except ValueError:
        return 0
