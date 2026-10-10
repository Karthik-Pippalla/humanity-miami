import json

from app.services.languages import language_clause, normalize_language


class ToolCallingUnsupported(RuntimeError):
    """The model or the API refused a tool-calling turn."""

WEIGHTS: dict[str, float | str] = {
    "flood_seconds_per_zone": 3 * 60,
    "flood_seconds_per_meter": 0.15,
    "event_seconds_per_event": 8 * 60,
    "note": "Penalties estimate mapped exposure. They are not a reported road closure or a live traffic delay.",
}


def score_route(duration_seconds: float, flood_zone_count: int, flood_overlap_meters: float, events_in_window: int) -> dict:
    flood_penalty = flood_zone_count * float(WEIGHTS["flood_seconds_per_zone"]) + flood_overlap_meters * float(
        WEIGHTS["flood_seconds_per_meter"]
    )
    event_penalty = events_in_window * float(WEIGHTS["event_seconds_per_event"])
    return {
        "duration_seconds": round(duration_seconds, 1),
        "flood_zone_count": flood_zone_count,
        "flood_overlap_meters": round(flood_overlap_meters, 1),
        "events_in_window": events_in_window,
        "flood_penalty_seconds": round(flood_penalty, 1),
        "event_penalty_seconds": round(event_penalty, 1),
        "total_seconds": round(duration_seconds + flood_penalty + event_penalty, 1),
        "weights": WEIGHTS,
    }


def explanation_facts(
    recommended_id: str,
    routes: list[dict],
    alerts: list[str],
    data_gaps: list[str],
    flood_active: bool = False,
) -> dict:
    return {
        "recommended_id": recommended_id,
        "closure": False,
        "flood_active": flood_active,
        "routes": routes,
        "weather_alert_headlines": alerts,
        "data_gaps": data_gaps,
        "instruction": (
            "Explain only these facts. Flood zones are shown only when flood_active is true. "
            "That exposure is a mapped special flood hazard area during an active alert, not a road closure. "
            "If flood_active is false, do not describe flooding as present. "
            "Mention every event in events_on_route by name. "
            "If affects_this_ride is false, use the when field and say that event will not affect this ride. "
            "If affects_this_ride is true, that overlap is estimated congestion near a scheduled venue, not measured traffic. "
            "Do not invent weather, closures, delays, or events that are absent here."
        ),
    }


def build_prompt(facts: dict, language: str = "en") -> str:
    return (
        "You write a short driving note for Survive Miami. Use only the JSON facts. "
        "Write 3 to 5 sentences. Say which route is recommended and why, using the scores. "
        "If closure is false, do not say any road is closed. "
        "If a data gap is listed, mention that source was unavailable. "
        "Mention every event in events_on_route by name and venue. "
        "When affects_this_ride is false, say when that event is and that it will not affect this ride. "
        "When affects_this_ride is true, say it may add estimated congestion near the venue, not measured traffic. "
        "Do not add traffic, rainfall, or events that are not in the facts. "
        f"{language_clause(language)}\n\n"
        f"{json.dumps(facts, indent=2)}"
    )


def _recommended_route(facts: dict) -> dict | None:
    routes = facts.get("routes") or []
    recommended = next((route for route in routes if route.get("id") == facts.get("recommended_id")), None)
    if recommended is None and routes:
        return routes[0]
    return recommended


def later_event_sentence(facts: dict) -> str:
    """Name shows later tonight or on a later day, and say they do not change this ride."""
    recommended = _recommended_route(facts)
    if recommended is None:
        return ""
    later = [event for event in (recommended.get("events_on_route") or []) if not event.get("affects_this_ride")]
    details = []
    for event in later[:3]:
        name = event.get("name")
        if not name:
            continue
        venue = event.get("venue")
        when = event.get("when")
        place = f"{name} at {venue}" if venue else str(name)
        details.append(f"{place} is {when}" if when else place)
    if not details:
        return ""
    subject = "That event" if len(details) == 1 else "Those events"
    return f"{'; '.join(details)}. {subject} will not affect this ride."


def with_later_events(text: str, facts: dict) -> str:
    sentence = later_event_sentence(facts)
    if not sentence:
        return text
    recommended = _recommended_route(facts) or {}
    names = [
        str(event.get("name"))
        for event in (recommended.get("events_on_route") or [])
        if not event.get("affects_this_ride") and event.get("name")
    ]
    lowered = text.casefold()
    named = all(name.casefold() in lowered for name in names[:3])
    says_no_effect = "not affect" in lowered or "won't affect" in lowered or "will not affect" in lowered
    if named and says_no_effect:
        return text
    return f"{text.rstrip()} {sentence}"


def explain_from_facts(facts: dict) -> str:
    """Plain-language note from computed scores. Does not call a model."""
    routes = facts.get("routes") or []
    recommended = _recommended_route(facts)
    if recommended is None:
        return "No route score was available to explain."

    sentences = [
        (
            f"{recommended['label']} is recommended. "
            f"It is about {recommended['duration_minutes']} minutes and {recommended['distance_km']} km."
        )
    ]
    gaps = facts.get("data_gaps") or []
    if "flood_zones_unavailable" in gaps:
        sentences.append("Flood-zone polygons could not be loaded, so flood exposure was not scored.")
    elif facts.get("flood_active"):
        crossed = int(recommended.get("flood_zones_crossed") or 0)
        if crossed:
            sentences.append(
                f"An active flood alert is in effect, and this drive crosses {crossed} mapped flood "
                f"{'zone' if crossed == 1 else 'zones'}. That is estimated exposure, not a road closure."
            )
        else:
            sentences.append(
                "An active flood alert is in effect, and this drive does not cross a mapped special flood hazard area."
            )
    else:
        sentences.append("No active flood alert is in effect, so flood areas are not part of this score.")

    listed = recommended.get("events_on_route") or []
    affecting = [event for event in listed if event.get("affects_this_ride")]
    later = [event for event in listed if not event.get("affects_this_ride")]
    if affecting:
        names = ", ".join(str(event.get("name")) for event in affecting[:3] if event.get("name"))
        sentences.append(
            f"{names} {'falls' if len(affecting) == 1 else 'fall'} in this departure window. "
            "That is estimated venue congestion, not measured traffic."
        )
    later_note = later_event_sentence(facts)
    if later_note:
        sentences.append(later_note)
    elif not affecting and not later:
        sentences.append("No listed event falls in this departure window.")

    alternatives = [route for route in routes if route.get("id") != recommended.get("id")]
    if alternatives:
        other = alternatives[0]
        sentences.append(
            f"{other['label']} is about {other['duration_minutes']} minutes. "
            "Its score is higher, so it is not the recommendation."
        )
    return " ".join(sentences)


class ExplainClient:
    def __init__(self, api_key: str, model: str):
        self.api_key = api_key
        self.model = model

    def explain(self, facts: dict, language: str = "en") -> str:
        return self.complete(build_prompt(facts, normalize_language(language)))

    def complete(self, prompt: str) -> str:
        response = self._generate(prompt, tools=None)
        text = (getattr(response, "text", None) or "").strip()
        if not text:
            raise RuntimeError("empty explanation")
        return text

    def open_tool_chat(self, tools: list):
        if not self.api_key:
            raise ToolCallingUnsupported("gemini_unconfigured")
        from google import genai
        from google.genai import types

        client = genai.Client(
            api_key=self.api_key,
            http_options=types.HttpOptions(timeout=50_000),
        )
        try:
            return client.chats.create(
                model=self.model,
                config=types.GenerateContentConfig(tools=tools),
            )
        except Exception as exc:
            raise ToolCallingUnsupported(str(exc)) from exc

    def send_tool_message(self, chat, message):
        try:
            return chat.send_message(message)
        except Exception as exc:
            raise ToolCallingUnsupported(str(exc)) from exc

    def _generate(self, prompt: str, tools: list | None):
        if not self.api_key:
            raise RuntimeError("gemini_unconfigured")
        from google import genai
        from google.genai import types

        client = genai.Client(
            api_key=self.api_key,
            http_options=types.HttpOptions(timeout=50_000),
        )
        config = types.GenerateContentConfig(tools=tools) if tools else None
        try:
            return client.models.generate_content(model=self.model, contents=prompt, config=config)
        except Exception as exc:
            if tools:
                raise ToolCallingUnsupported(str(exc)) from exc
            raise
