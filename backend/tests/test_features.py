import asyncio
import json
from datetime import datetime, timedelta
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.schemas import AssistRequest, Place, PlanRequest, PrepareRequest
from app.services.assistant import assist, prepare_checklist
from app.services.explain import ToolCallingUnsupported, build_prompt
from app.services.planner_agent import plan_itinerary
from app.services.traffic import TravelLeg
from app.services.weather import WeatherAlert, WeatherReport

MIAMI = ZoneInfo("America/New_York")
ORIGIN = Place(label="Little Havana", lat=25.765, lng=-80.22)


class QuietWeather:
    async def report(self, lat, lng):
        return WeatherReport(
            "Heavy rain",
            82,
            [WeatherAlert("Flood Warning", "Flood Warning for Miami-Dade", True)],
        )


class BrokenModel:
    api_key = "present"
    model = "gemma-4-26b-a4b-it"

    def complete(self, prompt):
        raise RuntimeError("model down")


class JsonModel:
    api_key = "present"
    model = "gemma-4-26b-a4b-it"

    def complete(self, prompt):
        assert "Spanish" in prompt
        return json.dumps({"items": [{"category": "Agua", "action": "Guarda agua", "why": "Hay una alerta"}]})


class Scripted:
    model = "gemma-4-26b-a4b-it"

    def __init__(self, replies):
        self.replies = list(replies)

    def complete(self, prompt):
        return self.replies.pop(0)


class NativeThenJson(Scripted):
    api_key = "present"

    def open_tool_chat(self, tools):
        raise ToolCallingUnsupported("tools rejected")


class FakeTraffic:
    used_fallback = True

    def __init__(self):
        self.calls = 0

    async def leg(self, origin, destination, depart_at, costing="auto"):
        self.calls += 1
        return TravelLeg(
            duration_seconds=600,
            distance_meters=4000,
            source="valhalla_typical",
            coordinates=[(origin.lat, origin.lng), (destination.lat, destination.lng)],
        )


class SilentModel:
    api_key = ""
    model = "gemma"


class RankedValhalla:
    async def route(self, origin, destination, exclude_polygons=None, depart_at=None, costing="auto"):
        minutes = {
            "American Red Cross of Greater Miami and the Keys": 4,
            "Jackson Memorial Hospital": 25,
        }.get(destination.label, 40)
        return SimpleNamespace(duration_seconds=minutes * 60, distance_meters=minutes * 800)


def test_prepare_uses_the_static_checklist_when_gemma_fails():
    result = asyncio.run(prepare_checklist(
        PrepareRequest(location=ORIGIN, pets=True, language="en"),
        QuietWeather(),
        BrokenModel(),
    ))
    assert result.model == "checklist"
    assert "gemini_unavailable" in result.data_gaps
    assert result.alerts == ["Flood Warning for Miami-Dade"]
    assert any("water" in item.action.casefold() for item in result.items)


def test_prepare_keeps_a_spanish_checklist_from_gemma():
    result = asyncio.run(prepare_checklist(
        PrepareRequest(location=ORIGIN, language="es"),
        QuietWeather(),
        JsonModel(),
    ))
    assert result.model == "gemma-4-26b-a4b-it"
    assert result.language == "es"
    assert result.items[0].action == "Guarda agua"
    assert result.data_gaps == []


def test_explain_prompt_names_the_requested_language():
    prompt = build_prompt({"closure": False}, "ht")
    assert "Haitian Creole" in prompt
    assert "not an official translation" in prompt


def test_assist_ranks_resources_by_drive_time():
    result = asyncio.run(assist(
        AssistRequest(location=ORIGIN, needs=["wheelchair", "elderly"], language="en"),
        QuietWeather(),
        RankedValhalla(),
        SilentModel(),
    ))
    assert result.resources[0].id == "red-cross-miami"
    assert result.resources[0].drive_minutes == 4
    assert result.resources[0].confirm.startswith("Confirm")
    assert all(item.id != "venetian-pool" for item in result.resources)
    assert result.model == "checklist"


def test_planner_recomputes_times_and_drops_unknown_stops():
    day = datetime(2026, 10, 11, 10, 0)
    traffic = FakeTraffic()
    model = Scripted([
        json.dumps({"action": "search_attractions", "interests": ["art"], "budget": "medium", "vibe": "relaxed"}),
        json.dumps({"action": "route_leg", "from_id": "start", "to_id": "vizcaya"}),
        json.dumps({"action": "weather_at", "lat": 25.76, "lng": -80.19}),
        json.dumps({
            "action": "finish",
            "stop_ids": ["vizcaya", "not-a-real-place"],
            "note": "A museum morning.",
        }),
    ])
    result = asyncio.run(plan_itinerary(
        PlanRequest(age=34, interests=["art"], budget="medium", vibe="relaxed", start=ORIGIN, day=day, language="en"),
        traffic,
        QuietWeather(),
        model,
    ))
    assert [stop.id for stop in result.stops] == ["vizcaya"]
    assert result.note == "A museum morning."
    assert result.stops[0].travel_minutes == 10
    arrival = datetime.fromisoformat(result.stops[0].arrival)
    assert arrival == day.replace(tzinfo=MIAMI) + timedelta(minutes=10)
    leave = datetime.fromisoformat(result.stops[0].leave)
    assert leave == arrival + timedelta(minutes=90)
    assert "planner_adjusted" in result.data_gaps
    assert result.timing_source == "valhalla_typical"
    assert "live_traffic_unavailable" in result.data_gaps
    assert traffic.calls == 2
    assert result.geometry["type"] == "LineString"


def test_planner_returns_the_catalog_when_gemma_is_too_slow():
    class SlowModel:
        api_key = ""
        model = "gemma-4-26b-a4b-it"

        def complete(self, prompt):
            import time

            time.sleep(0.4)
            return json.dumps({"action": "finish", "stop_ids": ["vizcaya"], "note": "late"})

    result = asyncio.run(plan_itinerary(
        PlanRequest(age=30, interests=["art"], budget="medium", vibe="relaxed", start=ORIGIN),
        FakeTraffic(),
        QuietWeather(),
        SlowModel(),
        model_budget=0.05,
    ))
    assert result.model == "catalog"
    assert "gemini_unavailable" in result.data_gaps
    assert result.stops


def test_planner_uses_json_actions_when_tool_calling_is_rejected():
    day = datetime(2026, 10, 11, 11, 0)
    result = asyncio.run(plan_itinerary(
        PlanRequest(age=40, interests=["art"], budget="medium", vibe="relaxed", start=ORIGIN, day=day),
        FakeTraffic(),
        QuietWeather(),
        NativeThenJson([json.dumps({"action": "finish", "stop_ids": ["pamm"], "note": "Bayfront art."})]),
    ))
    assert [stop.id for stop in result.stops] == ["pamm"]
    assert result.note == "Bayfront art."
    assert result.model == "gemma-4-26b-a4b-it"
