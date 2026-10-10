import json
import logging
import math

from app.schemas import (
    AdvisoryOut,
    AlertsOut,
    AssistRequest,
    AssistResponse,
    ChecklistItem,
    Place,
    PrepareRequest,
    PrepareResponse,
    ResourceOut,
)
from app.services.catalog import CONFIRM, matching_resources
from app.services.explain import ExplainClient
from app.services.languages import language_clause, normalize_language
from app.services.valhalla import ValhallaClient, ValhallaError
from app.services.weather import WeatherClient

logger = logging.getLogger(__name__)

PREPARE_NOTICE = (
    "This checklist is an explanation based on National Weather Service alerts and the notes you entered. "
    "It is not an official emergency order. Follow local instructions if they differ."
)
ASSIST_NOTICE = (
    "Nearby places come from a checked-in list of public Miami-Dade resources. "
    "Confirm a shelter or hospital is open before you go."
)

STATIC_CHECKLIST = [
    ChecklistItem(
        category="Water",
        action="Store one gallon of water per person per day for three days.",
        why="Storm and flood warnings in Miami can interrupt tap water.",
    ),
    ChecklistItem(
        category="Medicine",
        action="Keep a week of prescriptions and a written list of doses.",
        why="Pharmacies may close while a hurricane or storm warning is in effect.",
    ),
    ChecklistItem(
        category="Power",
        action="Charge phones and keep a battery pack in a dry bag.",
        why="Storms often cause power outages.",
    ),
    ChecklistItem(
        category="Go bag",
        action="Pack identification, cash, a flashlight, and a change of clothes.",
        why="You may need to leave quickly if an evacuation is ordered.",
    ),
    ChecklistItem(
        category="Pets",
        action="If you have pets, pack food, a leash, and a carrier.",
        why="Shelters expect pets to be under control.",
    ),
    ChecklistItem(
        category="Mobility",
        action="If you use a wheelchair or walker, arrange a ride before a warning is issued.",
        why="Special-needs transportation fills up as a storm approaches.",
    ),
    ChecklistItem(
        category="Information",
        action="Follow the National Weather Service headlines for your location and confirm shelter status with Miami-Dade.",
        why="A watch is not the same as a warning.",
    ),
]

STATIC_ASSIST_STEPS = [
    ChecklistItem(
        category="Confirm",
        action="Call or open the official page for a place before you leave.",
        why="Shelter assignments and hospital access change during an emergency.",
    ),
    ChecklistItem(
        category="Ride",
        action="If you do not drive, ask for a ride or special-needs transport early.",
        why="Travel gets harder after a warning is issued.",
    ),
    ChecklistItem(
        category="Bring",
        action="Bring medicines, a charger, identification, and mobility equipment you use every day.",
        why="A hospital or shelter may not have your specific supplies.",
    ),
]


def household_notes(body: PrepareRequest) -> str:
    parts = []
    if body.people:
        parts.append(f"People in the household: {body.people}.")
    if body.pets:
        parts.append("Pets live in the household.")
    if body.mobility.strip():
        parts.append(f"Mobility: {body.mobility.strip()}.")
    if body.medical.strip():
        parts.append(f"Medical needs: {body.medical.strip()}.")
    if body.notes.strip():
        parts.append(body.notes.strip())
    return " ".join(parts)


async def prepare_checklist(body: PrepareRequest, weather: WeatherClient, explain: ExplainClient) -> PrepareResponse:
    language = normalize_language(body.language)
    gaps: list[str] = []
    headlines: list[str] = []
    if body.location is not None:
        try:
            report = await weather.report(body.location.lat, body.location.lng)
            headlines = report.headlines
        except Exception:
            logger.warning("Weather lookup failed for a preparedness checklist", exc_info=True)
            gaps.append("weather_unavailable")
    else:
        gaps.append("weather_unavailable")
    facts = {
        "alerts": headlines,
        "household": household_notes(body),
        "instruction": (
            "Write a preparedness checklist using only these alerts and household notes. "
            "Do not invent shelter addresses, road closures, or alerts that are not listed."
        ),
    }
    items, model, model_gaps = await _checklist_from_model(facts, language, explain, STATIC_CHECKLIST, "preparedness checklist")
    return PrepareResponse(
        items=items,
        model=model,
        language=language,
        alerts=headlines,
        data_gaps=_unique(gaps + model_gaps),
        notice=PREPARE_NOTICE,
    )


async def assist(body: AssistRequest, weather: WeatherClient, valhalla: ValhallaClient, explain: ExplainClient) -> AssistResponse:
    language = normalize_language(body.language)
    gaps: list[str] = []
    headlines: list[str] = []
    try:
        report = await weather.report(body.location.lat, body.location.lng)
        headlines = report.headlines
    except Exception:
        logger.warning("Weather lookup failed for accessibility assistance", exc_info=True)
        gaps.append("weather_unavailable")
    resources, route_gaps = await _rank_resources(body.location, body.needs, valhalla)
    gaps.extend(route_gaps)
    facts = {
        "needs": body.needs,
        "alerts": headlines,
        "resources": [
            {"name": item.name, "kind": item.kind, "address": item.address, "drive_minutes": item.drive_minutes}
            for item in resources
        ],
        "instruction": (
            "Suggest preparation steps for these needs. Mention only resource names included here. "
            "Tell the person to confirm a site is open before going."
        ),
    }
    steps, model, model_gaps = await _checklist_from_model(facts, language, explain, STATIC_ASSIST_STEPS, "accessibility note")
    return AssistResponse(
        resources=resources,
        steps=steps,
        model=model,
        language=language,
        alerts=headlines,
        data_gaps=_unique(gaps + model_gaps),
        notice=ASSIST_NOTICE,
    )


async def translate_advisories(payload: AlertsOut, language: str, explain: ExplainClient) -> AlertsOut:
    language = normalize_language(language)
    payload.language = language
    if language == "en" or not payload.advisories:
        return payload
    facts = {
        "advisories": [
            {
                "event": item.event,
                "headline": item.headline,
                "severity": item.severity,
                "is_watch": item.is_watch,
                "instruction": item.instruction,
            }
            for item in payload.advisories
        ]
    }
    prompt = (
        "Explain each weather advisory in everyday words. Use only the JSON facts. "
        "Return a JSON object {\"lines\": [\"...\"]} with one line per advisory, in the same order. "
        "Do not add alerts that are not in the facts. "
        f"{language_clause(language)}\n\n{json.dumps(facts)}"
    )
    try:
        text = await _complete(explain, prompt)
        parsed = _extract_json(text)
        lines = parsed.get("lines") if isinstance(parsed, dict) else None
        if not isinstance(lines, list) or len(lines) != len(payload.advisories):
            raise ValueError("explanation did not match the advisories")
        updated: list[AdvisoryOut] = []
        for item, line in zip(payload.advisories, lines, strict=True):
            updated.append(item.model_copy(update={"plain_language": str(line).strip() or item.plain_language}))
        payload.advisories = updated
    except Exception:
        logger.warning("Plain-language alert explanation failed", exc_info=True)
        payload.data_gaps = _unique([*payload.data_gaps, "gemini_unavailable"])
    return payload


async def _rank_resources(origin: Place, needs: list[str], valhalla: ValhallaClient) -> tuple[list[ResourceOut], list[str]]:
    costing = "pedestrian" if "no_car" in {item.casefold() for item in needs} else "auto"
    candidates = matching_resources(needs)
    candidates.sort(key=lambda item: _distance_meters(origin.lat, origin.lng, item["lat"], item["lng"]))
    gaps: list[str] = []
    ranked: list[ResourceOut] = []
    for resource in candidates[:6]:
        destination = Place(label=resource["name"], lat=resource["lat"], lng=resource["lng"])
        minutes = None
        distance = _distance_meters(origin.lat, origin.lng, resource["lat"], resource["lng"])
        estimated = False
        try:
            route = await valhalla.route(origin, destination, costing=costing)
            minutes = round(route.duration_seconds / 60, 1)
            distance = route.distance_meters
        except ValhallaError:
            estimated = True
            speed = 48000 if costing == "auto" else 4000
            minutes = round((distance / speed) * 60, 1)
            if "routing_unavailable" not in gaps:
                gaps.append("routing_unavailable")
        ranked.append(
            ResourceOut(
                id=resource["id"],
                name=resource["name"],
                kind=resource["kind"],
                address=resource["address"],
                lat=resource["lat"],
                lng=resource["lng"],
                serves=list(resource["serves"]),
                source_url=resource["source_url"],
                drive_minutes=minutes,
                distance_meters=round(distance, 1),
                estimated=estimated,
                confirm=CONFIRM,
            )
        )
    ranked.sort(key=lambda item: item.drive_minutes if item.drive_minutes is not None else 1e9)
    return ranked[:5], gaps


async def _checklist_from_model(facts, language, explain: ExplainClient, fallback: list[ChecklistItem], label: str):
    if not explain.api_key:
        return fallback, "checklist", []
    prompt = (
        f"Write a {label} as JSON {{\"items\": [{{\"category\": \"...\", \"action\": \"...\", \"why\": \"...\"}}]}}. "
        "Use only the JSON facts. Return 4 to 7 items. "
        f"{language_clause(language)}\n\n{json.dumps(facts)}"
    )
    try:
        text = await _complete(explain, prompt)
        parsed = _extract_json(text)
        raw_items = parsed.get("items") if isinstance(parsed, dict) else None
        items = _items(raw_items)
        if not items:
            raise ValueError("empty checklist")
        return items, explain.model, []
    except Exception:
        logger.warning("Gemma checklist failed; using the static list", exc_info=True)
        return fallback, "checklist", ["gemini_unavailable"]


def _items(raw) -> list[ChecklistItem]:
    if not isinstance(raw, list):
        return []
    items: list[ChecklistItem] = []
    for row in raw[:7]:
        if not isinstance(row, dict):
            continue
        action = str(row.get("action") or "").strip()
        if not action:
            continue
        items.append(
            ChecklistItem(
                category=str(row.get("category") or "Prepare").strip() or "Prepare",
                action=action,
                why=str(row.get("why") or "").strip() or "Based on the details you provided.",
            )
        )
    return items


async def _complete(explain: ExplainClient, prompt: str) -> str:
    import asyncio

    return await asyncio.to_thread(explain.complete, prompt)


def _extract_json(text: str):
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:]
    start_obj = cleaned.find("{")
    end_obj = cleaned.rfind("}")
    if start_obj >= 0 and end_obj > start_obj:
        return json.loads(cleaned[start_obj : end_obj + 1])
    raise ValueError("no json object")


def _distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    radius = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    chord = math.sin(d_lat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(d_lng / 2) ** 2
    return 2 * radius * math.asin(min(1, math.sqrt(chord)))


def _unique(items: list[str]) -> list[str]:
    return list(dict.fromkeys(items))
