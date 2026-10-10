import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from shapely.geometry import LineString, Polygon

from app.geo import (
    avoidance_rings,
    bbox_of_line,
    geojson_line,
    hits_along,
    in_south_florida,
    length_meters,
)

logger = logging.getLogger(__name__)
from app.schemas import (
    EventHit,
    EventZoneOut,
    ExplanationOut,
    FloodExposure,
    FloodZoneOut,
    Place,
    RouteCandidate,
    RouteManeuver,
    ScoreBreakdown,
    TripRequest,
    TripResponse,
    WeatherOut,
)
from app.services.events import LiveEvent
from app.services.explain import ExplainClient, explain_from_facts, explanation_facts, score_route, with_later_events
from app.services.flood import FLOOD_SOURCE, FloodClient, FloodZone
from app.services.valhalla import RawRoute, ValhallaClient, ValhallaError
from app.services.weather import WeatherClient

MIAMI = ZoneInfo("America/New_York")
NOTICE = (
    "Travel time is a typical drive from the routing engine, not live traffic. "
    "Flood areas are shown only during an active National Weather Service flood warning or advisory. "
    "They are estimated exposure, not a reported road closure."
)


class OutsideArea(Exception):
    pass


@dataclass
class Services:
    valhalla: ValhallaClient
    flood: FloodClient
    weather: WeatherClient
    events: object
    explain: ExplainClient


def _as_miami(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=MIAMI)
    return value.astimezone(MIAMI)


def _event_hits(line: LineString, events: list[LiveEvent], depart: datetime) -> list[tuple[LiveEvent, bool, bool]]:
    rows: list[tuple[LiveEvent, bool, bool]] = []
    for event in events:
        polygon = Polygon(event.ring)
        intersects = length_meters(line.intersection(polygon)) >= 25
        window = event.window()
        in_window = bool(window and window[0] <= depart <= window[1])
        if intersects or in_window:
            rows.append((event, intersects, in_window))
    return rows


def _candidate(
    route_id: str,
    label: str,
    route: RawRoute,
    flood_zones: list[FloodZone],
    events: list[LiveEvent],
    depart: datetime,
    flood_active: bool,
    alerts_known: bool,
) -> tuple[RouteCandidate, list[FloodZone]]:
    line: LineString = route.line
    flood_hits = hits_along(line, [(zone.id, zone.geometry) for zone in flood_zones]) if flood_active else []
    overlap = sum(hit.overlap_meters for hit in flood_hits)
    event_rows = _event_hits(line, events, depart)
    in_window = [event for event, intersects, inside in event_rows if intersects and inside]
    zone_lookup = {zone.id: zone for zone in flood_zones}
    names = [zone_lookup[hit.zone_id].zone for hit in flood_hits if hit.zone_id in zone_lookup]
    if not alerts_known:
        summary = "Flood areas are hidden because current flood alerts could not be checked."
    elif not flood_active:
        summary = "No active flood alert, so flood areas are not shown."
    elif names:
        summary = (
            "An active flood alert is in effect. Estimated exposure: the drive crosses mapped flood zone "
            f"{', '.join(dict.fromkeys(names))}. This is not a reported road closure."
        )
    else:
        summary = "An active flood alert is in effect. This drive does not cross a mapped special flood hazard area."
    scored = score_route(route.duration_seconds, len(flood_hits), overlap, len(in_window))
    candidate = RouteCandidate(
        id=route_id,
        label=label,
        geometry=geojson_line(line),
        duration_seconds=route.duration_seconds,
        distance_meters=route.distance_meters,
        has_toll=route.has_toll,
        flood=FloodExposure(
            intersecting=bool(flood_hits),
            zone_ids=[hit.zone_id for hit in flood_hits],
            overlap_meters=round(overlap, 1),
            summary=summary,
        ),
        events=[
            EventHit(
                id=event.id,
                name=event.name,
                venue=event.venue,
                start=event.start.isoformat() if event.start else None,
                end=event.end.isoformat() if event.end else None,
                intersects_route=intersects,
                in_departure_window=inside,
            )
            for event, intersects, inside in event_rows
            if intersects
        ],
        score=ScoreBreakdown(**scored),
        maneuvers=[
            RouteManeuver(
                type=step.type,
                instruction=step.instruction,
                length_meters=round(step.length_meters, 1),
                time_seconds=round(step.time_seconds, 1),
                begin_shape_index=step.begin_shape_index,
                end_shape_index=step.end_shape_index,
            )
            for step in route.maneuvers
        ],
    )
    drawn = [zone_lookup[hit.zone_id] for hit in flood_hits if hit.zone_id in zone_lookup]
    return candidate, drawn


def _perimeter(rings: list[list[list[float]]]) -> float:
    return sum(length_meters(Polygon(ring).exterior) for ring in rings)


def _with_events(
    rings: list[list[list[float]]], line: LineString, events: list[LiveEvent], depart: datetime
) -> list[list[list[float]]]:
    kept = list(rings)
    for event in events:
        window = event.window()
        if window is None or not (window[0] <= depart <= window[1]):
            continue
        polygon = Polygon(event.ring)
        if length_meters(line.intersection(polygon)) < 25:
            continue
        if len(kept) >= 8 or _perimeter(kept + [event.ring]) > 8500:
            break
        kept.append(event.ring)
    return kept


def _avoid_polygons(line: LineString, zones: list[FloodZone], events: list[LiveEvent], depart: datetime) -> list[list[list[float]]]:
    rings: list[list[list[float]]] = []
    hits = hits_along(line, [(zone.id, zone.geometry) for zone in zones])
    zone_lookup = {zone.id: zone for zone in zones}
    for hit in sorted(hits, key=lambda item: item.overlap_meters, reverse=True)[:4]:
        zone = zone_lookup[hit.zone_id]
        for ring in avoidance_rings(line, zone.geometry, radius_m=70, chunk_m=500, limit=2):
            if _perimeter(rings + [ring]) > 8500:
                return _with_events(rings, line, events, depart)
            rings.append(ring)
            if len(rings) >= 6:
                return _with_events(rings, line, events, depart)
    return _with_events(rings, line, events, depart)


def _same_drive(left: RawRoute, right: RawRoute) -> bool:
    return abs(left.duration_seconds - right.duration_seconds) < 20 and abs(left.distance_meters - right.distance_meters) < 200


def _event_when(start: str | None, depart: datetime) -> str | None:
    if not start:
        return None
    parsed = datetime.fromisoformat(start)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=MIAMI)
    start_local = parsed.astimezone(MIAMI)
    depart_local = depart.astimezone(MIAMI)
    clock = start_local.strftime("%I:%M %p").lstrip("0")
    if start_local <= depart_local:
        return None
    if start_local.date() == depart_local.date():
        part = "later tonight" if start_local.hour >= 17 else "later today"
        return f"{part} at {clock}"
    if start_local.date() == depart_local.date() + timedelta(days=1):
        return f"tomorrow at {clock}"
    return f"on {start_local.strftime('%b')} {start_local.day} at {clock}"


def _route_facts(candidate: RouteCandidate, depart: datetime) -> dict:
    return {
        "id": candidate.id,
        "label": candidate.label,
        "duration_minutes": round(candidate.duration_seconds / 60, 1),
        "distance_km": round(candidate.distance_meters / 1000, 2),
        "flood_zones_crossed": len(candidate.flood.zone_ids),
        "flood_overlap_meters": candidate.flood.overlap_meters,
        "events_in_departure_window": sum(1 for event in candidate.events if event.in_departure_window),
        "events_on_route": [
            {
                "name": event.name,
                "venue": event.venue,
                "start": event.start,
                "when": _event_when(event.start, depart),
                "in_departure_window": event.in_departure_window,
                "affects_this_ride": event.in_departure_window,
            }
            for event in candidate.events
        ],
        "score_seconds": candidate.score.total_seconds,
        "closure": False,
    }


async def plan_trip(request: TripRequest, services: Services) -> TripResponse:
    for place in (request.origin, request.destination):
        if not in_south_florida(place.lat, place.lng):
            raise OutsideArea("Survive Miami currently routes in South Florida.")
    if abs(request.origin.lat - request.destination.lat) < 0.0001 and abs(request.origin.lng - request.destination.lng) < 0.0001:
        raise OutsideArea("Choose two different places.")

    depart = _as_miami(request.depart_at or datetime.now(MIAMI))
    gaps: list[str] = []
    fastest = await services.valhalla.route(request.origin, request.destination)
    min_lng, min_lat, max_lng, max_lat = bbox_of_line(fastest.line, 0.03)
    midpoint = Place(
        label="midpoint",
        lat=(request.origin.lat + request.destination.lat) / 2,
        lng=(request.origin.lng + request.destination.lng) / 2,
    )

    flood_zones: list[FloodZone] = []
    weather = None
    events: list[LiveEvent] = []

    async def load_weather():
        return await services.weather.report(midpoint.lat, midpoint.lng)

    async def load_events():
        return await services.events.nearby(midpoint, depart)

    weather_result, event_result = await asyncio.gather(load_weather(), load_events(), return_exceptions=True)
    if isinstance(weather_result, Exception):
        gaps.append("weather_unavailable")
    else:
        weather = weather_result
    if isinstance(event_result, Exception):
        gaps.append("events_unavailable")
    else:
        events, event_gaps = event_result
        gaps.extend(event_gaps)

    flood_active = bool(weather and weather.flood_active)
    alerts_known = weather is not None
    if flood_active:
        try:
            flood_zones, flood_gaps = await services.flood.zones_in_bbox(min_lng, min_lat, max_lng, max_lat)
            gaps.extend(flood_gaps)
        except Exception:
            gaps.append("flood_zones_unavailable")

    fastest_candidate, fastest_zones = _candidate(
        "fastest", "Fastest drive", fastest, flood_zones, events, depart, flood_active, alerts_known
    )
    routes = [fastest_candidate]
    drawn: dict[str, FloodZone] = {zone.id: zone for zone in fastest_zones}

    avoid = _avoid_polygons(fastest.line, flood_zones, events, depart)
    if avoid:
        try:
            alternate = await services.valhalla.route(request.origin, request.destination, avoid)
            if not _same_drive(fastest, alternate):
                alternate_candidate, alternate_zones = _candidate(
                    "detour",
                    "Avoidance detour",
                    alternate,
                    flood_zones,
                    events,
                    depart,
                    flood_active,
                    alerts_known,
                )
                routes.append(alternate_candidate)
                for zone in alternate_zones:
                    drawn[zone.id] = zone
        except ValhallaError as exc:
            logger.warning("Avoidance route failed: %s", exc)
            gaps.append("valhalla_avoid_failed")

    recommended = min(routes, key=lambda route: route.score.total_seconds)
    alerts = weather.headlines if weather else []
    facts = explanation_facts(
        recommended.id, [_route_facts(route, depart) for route in routes], alerts, gaps, flood_active=flood_active
    )

    event_zones = []
    for event in events:
        window = event.window()
        in_window = bool(window and window[0] <= depart <= window[1])
        intersects = any(hit.id == event.id for route in routes for hit in route.events)
        if not intersects and not in_window:
            continue
        event_zones.append(
            EventZoneOut(
                id=event.id,
                name=event.name,
                venue=event.venue,
                start=event.start.isoformat() if event.start else None,
                end=event.end.isoformat() if event.end else None,
                ring=event.ring,
                intersects_route=intersects,
                in_departure_window=in_window,
            )
        )

    flood_out = []
    for zone in drawn.values():
        ring = zone.ring
        if ring:
            flood_out.append(FloodZoneOut(id=zone.id, zone=zone.zone, subtype=zone.subtype, ring=ring))

    return TripResponse(
        origin=request.origin,
        destination=request.destination,
        recommended_id=recommended.id,
        routes=routes,
        flood_zones=flood_out[:40],
        event_zones=event_zones[:15],
        weather=WeatherOut(
            forecast=weather.forecast,
            temperature_f=weather.temperature_f,
            alerts=weather.headlines,
            flood_active=weather.flood_active,
        )
        if weather
        else None,
        explanation=None,
        explanation_facts=facts,
        data_gaps=list(dict.fromkeys(gaps)),
        sources={
            "routing": "Valhalla",
            "flood": FLOOD_SOURCE,
            "weather": "National Weather Service",
            "events": "Ticketmaster Discovery",
            "explanation": None,
            "map": "Google Maps",
        },
        notice=NOTICE,
    )


async def write_explanation(
    facts: dict, explain: ExplainClient, language: str = "en"
) -> tuple[ExplanationOut, list[str]]:
    """Ask Gemma to rewrite the computed facts. The score note is used if Gemma does not finish."""
    fallback = ExplanationOut(text=explain_from_facts(facts), model="route-scores")
    if not explain.api_key:
        return fallback, []
    task = asyncio.create_task(asyncio.to_thread(explain.explain, facts, language))
    done, _pending = await asyncio.wait({task}, timeout=52)
    if not done:
        logger.warning("Gemma explanation timed out; using the score note")
        return fallback, ["gemini_unavailable"]
    try:
        text = task.result()
    except Exception:
        logger.warning("Gemma explanation failed", exc_info=True)
        return fallback, ["gemini_unavailable"]
    if not text:
        return fallback, ["gemini_unavailable"]
    return ExplanationOut(text=with_later_events(text, facts), model=explain.model), []

