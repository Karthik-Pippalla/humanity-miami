from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.schemas import ItineraryStop, Place, PlanRequest, PlanResponse
from app.services.catalog import attraction_by_id, search_attractions
from app.services.explain import ToolCallingUnsupported
from app.services.languages import language_clause, normalize_language
from app.services.traffic import TrafficClient
from app.services.weather import WeatherClient

logger = logging.getLogger(__name__)
MIAMI = ZoneInfo("America/New_York")
MAX_STOPS = 4
MAX_STEPS = 6
# Firebase Hosting closes the Cloud Run rewrite at 60 seconds. Leave room for the drive legs.
MODEL_BUDGET_SECONDS = 16
LEG_BUDGET_SECONDS = 6

NOTICES = {
    "google_traffic": (
        "Drive times use Google traffic-aware estimates for each departure. "
        "The next stop starts after the previous visit and that drive."
    ),
    "valhalla_typical": (
        "Live traffic was unavailable. Drive times are a typical drive for the time of day, not live traffic. "
        "The next stop starts after the previous visit and that drive."
    ),
}


async def plan_itinerary(
    body: PlanRequest,
    traffic: TrafficClient,
    weather: WeatherClient,
    model,
    model_budget: float = MODEL_BUDGET_SECONDS,
) -> PlanResponse:
    language = normalize_language(body.language)
    session = _Session(body, traffic, weather)
    finished = None
    gaps: list[str] = []
    try:
        finished = await asyncio.wait_for(_ask_model(model, body, session), timeout=model_budget)
    except TimeoutError:
        logger.warning("Plan Miami agent exceeded %.0fs", model_budget)
        gaps.append("gemini_unavailable")
    except Exception:
        logger.warning("Plan Miami agent failed", exc_info=True)
        gaps.append("gemini_unavailable")
    return await _materialize(body, finished, session, traffic, language, gaps, getattr(model, "model", "gemma"))


async def _ask_model(model, body: PlanRequest, session: _Session) -> dict | None:
    finished = None
    if getattr(model, "api_key", "") and hasattr(model, "open_tool_chat"):
        try:
            finished = await _native_loop(model, body, session)
        except ToolCallingUnsupported:
            logger.info("Gemma tool calling is unavailable; using JSON actions")
            finished = None
    if finished is None:
        finished = await _json_loop(model, body, session)
    return finished


class _Session:
    def __init__(self, body: PlanRequest, traffic: TrafficClient, weather: WeatherClient):
        self.body = body
        self.traffic = traffic
        self.weather = weather
        self.catalog = attraction_by_id()

    async def dispatch(self, action: dict) -> dict:
        name = str(action.get("action") or "")
        if name == "search_attractions":
            return self._search(action)
        if name == "route_leg":
            return await self._route(action)
        if name == "weather_at":
            return await self._weather(action)
        return {"error": "Use search_attractions, route_leg, weather_at, or finish."}

    def _search(self, action: dict) -> dict:
        interests = _strings(action.get("interests")) or list(self.body.interests)
        budget = str(action.get("budget") or self.body.budget)
        vibe = str(action.get("vibe") or self.body.vibe)
        needs = _strings(action.get("needs")) or list(self.body.needs)
        age = int(action.get("age") or self.body.age)
        places, relaxed = search_attractions(interests, budget, vibe, needs, age)
        return {
            "relaxed_filters": relaxed,
            "places": [
                {
                    "id": place["id"],
                    "name": place["name"],
                    "lat": place["lat"],
                    "lng": place["lng"],
                    "dwell_minutes": place["dwell_minutes"],
                    "interests": place["interests"],
                    "why": place["why"],
                }
                for place in places
            ],
        }

    async def _route(self, action: dict) -> dict:
        origin = self._place(action.get("from_id") or "start")
        destination = self._place(action.get("to_id"))
        if origin is None or destination is None:
            return {"error": "from_id and to_id must be start or a catalog id."}
        depart = _parse_time(action.get("depart_at")) or _day(self.body)
        try:
            leg = await self.traffic.leg(origin, destination, depart)
        except Exception as exc:
            return {"error": str(exc) or "route_unavailable"}
        return {
            "from_id": action.get("from_id") or "start",
            "to_id": action.get("to_id"),
            "duration_minutes": round(leg.duration_seconds / 60, 1),
            "distance_meters": round(leg.distance_meters, 1),
            "source": leg.source,
        }

    async def _weather(self, action: dict) -> dict:
        lat = action.get("lat", self.body.start.lat)
        lng = action.get("lng", self.body.start.lng)
        try:
            report = await self.weather.report(float(lat), float(lng))
        except Exception:
            return {"error": "weather_unavailable"}
        return {"forecast": report.forecast, "alerts": report.headlines, "flood_active": report.flood_active}

    def _place(self, place_id) -> Place | None:
        if place_id in (None, "", "start"):
            return self.body.start
        place = self.catalog.get(str(place_id))
        if place is None:
            return None
        return Place(label=place["name"], lat=place["lat"], lng=place["lng"])


async def _native_loop(model, body: PlanRequest, session: _Session) -> dict | None:
    from google.genai import types

    chat = model.open_tool_chat(_tool_declarations())
    message: object = _opening(body) + "\n" + _tool_hint()
    for _ in range(MAX_STEPS):
        response = await asyncio.to_thread(model.send_tool_message, chat, message)
        calls = list(getattr(response, "function_calls", None) or [])
        if not calls:
            action = _parse_action(getattr(response, "text", "") or "")
            if action and action.get("action") == "finish":
                return action
            if not action:
                return None
            observation = await session.dispatch(action)
            message = json.dumps({"observation": observation})
            continue
        parts = []
        for call in calls:
            action = {"action": getattr(call, "name", ""), **_call_args(call)}
            if action["action"] == "finish":
                return action
            observation = await session.dispatch(action)
            parts.append(types.Part.from_function_response(name=action["action"], response={"result": observation}))
        message = parts
    return None


async def _json_loop(model, body: PlanRequest, session: _Session) -> dict | None:
    transcript = [_opening(body), _json_instructions()]
    for _ in range(MAX_STEPS):
        raw = await asyncio.to_thread(model.complete, "\n".join(transcript))
        action = _parse_action(raw)
        if not action:
            transcript.append("Reply with one JSON object only.")
            continue
        if action.get("action") == "finish":
            return action
        observation = await session.dispatch(action)
        transcript.append(raw)
        transcript.append(json.dumps({"observation": observation}))
    return None


async def _materialize(body, finished, session, traffic: TrafficClient, language: str, gaps: list[str], model_name: str):
    catalog = session.catalog
    requested = _strings((finished or {}).get("stop_ids"))
    chosen = []
    dropped = False
    for stop_id in requested:
        place = catalog.get(stop_id)
        if place is None or any(item["id"] == stop_id for item in chosen):
            dropped = True
            continue
        chosen.append(place)
        if len(chosen) == MAX_STOPS:
            break
    model = model_name
    note = str((finished or {}).get("note") or "").strip()
    if not chosen:
        places, _relaxed = search_attractions(body.interests, body.budget, body.vibe, body.needs, body.age)
        chosen = list(places[:3])
        dropped = True
        model = "catalog"
        if "gemini_unavailable" not in gaps:
            gaps.append("gemini_unavailable")
        if not note:
            note = "This itinerary is chosen from the Miami catalog because a finished plan was not available."
    elif dropped:
        gaps.append("planner_adjusted")
    if not note:
        note = "The stops below are from the Miami catalog, and the times follow the routed drives."

    cursor = _day(body)
    previous = body.start
    stops: list[ItineraryStop] = []
    coordinates: list[list[float]] = [[round(body.start.lng, 6), round(body.start.lat, 6)]]
    for place in chosen:
        destination = Place(label=place["name"], lat=place["lat"], lng=place["lng"])
        travel_minutes = None
        try:
            leg = await asyncio.wait_for(traffic.leg(previous, destination, cursor), timeout=LEG_BUDGET_SECONDS)
            travel_minutes = round(leg.duration_seconds / 60, 1)
            cursor = cursor + timedelta(seconds=leg.duration_seconds)
            _append_coords(coordinates, leg.coordinates)
        except Exception:
            logger.warning("Plan leg failed", exc_info=True)
            if "routing_unavailable" not in gaps:
                gaps.append("routing_unavailable")
            _append_coords(coordinates, [(previous.lat, previous.lng), (destination.lat, destination.lng)])
        arrival = cursor
        dwell = int(place["dwell_minutes"])
        leave = arrival + timedelta(minutes=dwell)
        stops.append(
            ItineraryStop(
                id=place["id"],
                name=place["name"],
                lat=place["lat"],
                lng=place["lng"],
                arrival=_clock(arrival),
                dwell_minutes=dwell,
                leave=_clock(leave),
                travel_minutes=travel_minutes,
                why=place["why"],
            )
        )
        previous = destination
        cursor = leave

    if traffic.used_fallback and "live_traffic_unavailable" not in gaps:
        gaps.append("live_traffic_unavailable")
    source = "valhalla_typical" if traffic.used_fallback else "google_traffic"
    return PlanResponse(
        stops=stops,
        geometry={"type": "LineString", "coordinates": coordinates},
        note=note,
        model=model,
        timing_source=source,
        language=language,
        data_gaps=list(dict.fromkeys(gaps)),
        notice=NOTICES[source],
    )


def _opening(body: PlanRequest) -> str:
    profile = {
        "age": body.age,
        "interests": body.interests,
        "budget": body.budget,
        "vibe": body.vibe,
        "needs": body.needs,
        "start": {"label": body.start.label, "lat": body.start.lat, "lng": body.start.lng},
        "day": _clock(_day(body)),
        "language": normalize_language(body.language),
    }
    return (
        "You are the Plan Miami agent. Build a one-day Miami itinerary for this profile. "
        "Choose stops only from search_attractions results. Do not invent places. "
        f"{language_clause(body.language)}\n"
        f"{json.dumps(profile)}"
    )


def _tool_hint() -> str:
    return "Call search_attractions, then route_leg and weather_at as needed, then finish."


def _json_instructions() -> str:
    return (
        "Reply with one JSON object per turn. Actions: "
        '{"action":"search_attractions","interests":[],"budget":"medium","vibe":"relaxed","needs":[],"age":30} '
        '{"action":"route_leg","from_id":"start","to_id":"vizcaya","depart_at":"2026-10-11T10:00:00"} '
        '{"action":"weather_at","lat":25.78,"lng":-80.19} '
        '{"action":"finish","stop_ids":["vizcaya"],"note":"A short note in the requested language."}'
    )


def _tool_declarations():
    from google.genai import types

    object_schema = {
        "search_attractions": {
            "type": "object",
            "properties": {
                "interests": {"type": "array", "items": {"type": "string"}},
                "budget": {"type": "string"},
                "vibe": {"type": "string"},
                "needs": {"type": "array", "items": {"type": "string"}},
                "age": {"type": "integer"},
            },
        },
        "route_leg": {
            "type": "object",
            "properties": {
                "from_id": {"type": "string"},
                "to_id": {"type": "string"},
                "depart_at": {"type": "string"},
            },
            "required": ["to_id"],
        },
        "weather_at": {
            "type": "object",
            "properties": {"lat": {"type": "number"}, "lng": {"type": "number"}},
        },
        "finish": {
            "type": "object",
            "properties": {
                "stop_ids": {"type": "array", "items": {"type": "string"}},
                "note": {"type": "string"},
            },
            "required": ["stop_ids", "note"],
        },
    }
    descriptions = {
        "search_attractions": "Filter the Miami attraction catalog.",
        "route_leg": "Travel time from start or a catalog id to a catalog id.",
        "weather_at": "National Weather Service snapshot for a point.",
        "finish": "Publish the ordered catalog stop ids and a short note.",
    }
    declarations = [
        types.FunctionDeclaration(name=name, description=descriptions[name], parameters_json_schema=schema)
        for name, schema in object_schema.items()
    ]
    return [types.Tool(function_declarations=declarations)]


def _parse_action(text: str) -> dict | None:
    cleaned = (text or "").strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:]
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        payload = json.loads(cleaned[start : end + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict) or "action" not in payload:
        return None
    return payload


def _call_args(call) -> dict:
    raw = getattr(call, "args", None) or {}
    return dict(raw) if hasattr(raw, "items") else {}


def _strings(value) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if str(item).strip()]


def _day(body: PlanRequest) -> datetime:
    if body.day is None:
        return datetime.now(MIAMI)
    if body.day.tzinfo is None:
        return body.day.replace(tzinfo=MIAMI)
    return body.day.astimezone(MIAMI)


def _parse_time(value) -> datetime | None:
    if not value:
        return None
    text = str(value).strip()
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=MIAMI)
    return parsed.astimezone(MIAMI)


def _clock(value: datetime) -> str:
    return value.astimezone(MIAMI).isoformat(timespec="seconds")


def _append_coords(coordinates: list[list[float]], points: list[tuple[float, float]]) -> None:
    for lat, lng in points:
        point = [round(float(lng), 6), round(float(lat), 6)]
        if coordinates and coordinates[-1] == point:
            continue
        coordinates.append(point)
