from dataclasses import dataclass, field
from datetime import datetime
from zoneinfo import ZoneInfo

import httpx

from app.geo import decode_polyline, line_from_latlng
from app.schemas import Place

MIAMI = ZoneInfo("America/New_York")


class ValhallaError(Exception):
    pass


@dataclass
class RawManeuver:
    type: int
    instruction: str
    length_meters: float
    time_seconds: float
    begin_shape_index: int
    end_shape_index: int


@dataclass
class RawRoute:
    line: object
    duration_seconds: float
    distance_meters: float
    has_toll: bool
    maneuvers: list[RawManeuver] = field(default_factory=list)


def parse_maneuvers(leg: dict, point_count: int) -> list[RawManeuver]:
    """Valhalla lengths follow the requested units. This client asks for kilometers."""
    last = max(point_count - 1, 0)
    rows: list[RawManeuver] = []
    for item in leg.get("maneuvers") or []:
        instruction = str(item.get("instruction") or "").strip()
        if not instruction:
            continue
        begin = int(item.get("begin_shape_index") or 0)
        end = int(item.get("end_shape_index") or begin)
        begin = min(max(begin, 0), last)
        end = min(max(end, begin), last)
        rows.append(
            RawManeuver(
                type=int(item.get("type") or 0),
                instruction=instruction,
                length_meters=float(item.get("length") or 0) * 1000,
                time_seconds=float(item.get("time") or 0),
                begin_shape_index=begin,
                end_shape_index=end,
            )
        )
    return rows


class ValhallaClient:
    def __init__(self, base_url: str, client: httpx.AsyncClient):
        self.base_url = base_url.rstrip("/")
        self.client = client

    async def route(
        self,
        origin: Place,
        destination: Place,
        exclude_polygons: list[list[list[float]]] | None = None,
        depart_at: datetime | None = None,
        costing: str = "auto",
    ) -> RawRoute:
        body: dict = {
            "locations": [
                {"lat": origin.lat, "lon": origin.lng},
                {"lat": destination.lat, "lon": destination.lng},
            ],
            "costing": costing,
            "units": "kilometers",
        }
        if depart_at is not None:
            local = depart_at.astimezone(MIAMI) if depart_at.tzinfo else depart_at
            body["date_time"] = {"type": 1, "value": local.strftime("%Y-%m-%dT%H:%M")}
        if exclude_polygons:
            body["exclude_polygons"] = exclude_polygons
        try:
            response = await self.client.post(f"{self.base_url}/route", json=body, timeout=25)
        except httpx.HTTPError as exc:
            raise ValhallaError("The routing engine could not be reached.") from exc
        if response.status_code >= 400:
            message = "No driving route was returned for those points."
            try:
                payload = response.json()
                message = payload.get("error") or payload.get("message") or message
            except ValueError:
                pass
            raise ValhallaError(str(message))
        trip = response.json().get("trip") or {}
        legs = trip.get("legs") or []
        if not legs or not legs[0].get("shape"):
            raise ValhallaError("The routing engine returned an empty route.")
        decoded = decode_polyline(legs[0]["shape"], 6)
        if len(decoded) < 2:
            raise ValhallaError("The routing engine returned an empty route.")
        summary = trip.get("summary") or {}
        length_km = float(summary.get("length") or 0)
        return RawRoute(
            line=line_from_latlng(decoded),
            duration_seconds=float(summary.get("time") or 0),
            distance_meters=length_km * 1000,
            has_toll=bool(summary.get("has_toll")),
            maneuvers=parse_maneuvers(legs[0], len(decoded)),
        )
