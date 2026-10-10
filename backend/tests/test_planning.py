from datetime import datetime
from zoneinfo import ZoneInfo

import asyncio

import pytest
from shapely.geometry import LineString, box

from app.planning import Services, _event_when, plan_trip, write_explanation
from app.schemas import Place, TripRequest
from app.services.explain import WEIGHTS, build_prompt, explain_from_facts, explanation_facts, score_route, with_later_events
from app.services.flood import FloodZone
from app.services.valhalla import RawRoute, ValhallaError

MIAMI = ZoneInfo("America/New_York")
ORIGIN = Place(label="Calle Ocho", lat=25.7653, lng=-80.2196)
DEST = Place(label="Miami Beach Convention Center", lat=25.7907, lng=-80.1300)


class FakeValhalla:
    def __init__(self, alternate_duration: float = 1100, fail_avoid: bool = False):
        self.alternate_duration = alternate_duration
        self.fail_avoid = fail_avoid
        self.exclude_calls = 0

    async def route(self, origin, destination, exclude_polygons=None):
        if exclude_polygons:
            self.exclude_calls += 1
            if self.fail_avoid:
                raise ValhallaError("avoid rejected")
            line = LineString([(-80.22, 25.82), (-80.13, 25.83)])
            return RawRoute(line, self.alternate_duration, 14000, False)
        line = LineString([(-80.22, 25.76), (-80.17, 25.77), (-80.13, 25.79)])
        return RawRoute(line, 800, 10000, True)


class FakeFlood:
    async def zones_in_bbox(self, *args):
        zone = FloodZone("md-1", "AE", None, box(-80.185, 25.755, -80.155, 25.785))
        return [zone], []


class BrokenFlood:
    async def zones_in_bbox(self, *args):
        raise RuntimeError("gis down")


class FakeWeather:
    async def report(self, lat, lng):
        from app.services.weather import WeatherAlert, WeatherReport

        return WeatherReport(
            "Partly cloudy",
            84,
            [WeatherAlert("Flood Warning", "Flood Warning for Miami-Dade", True)],
        )


class CalmWeather:
    async def report(self, lat, lng):
        from app.services.weather import WeatherReport

        return WeatherReport("Partly cloudy", 84, [])


class FakeEvents:
    async def nearby(self, center, depart):
        return [], ["ticketmaster_unconfigured"]


class FakeExplain:
    def __init__(self, api_key="test-key"):
        self.api_key = api_key
        self.model = "gemma-4-26b-a4b-it"
        self.facts = None

    def explain(self, facts, language="en"):
        self.facts = facts
        self.language = language
        return "The lower exposure drive is recommended because the fastest drive crosses a mapped flood zone."


def _services(valhalla=None, flood=None, explain=None, weather=None) -> Services:
    return Services(
        valhalla=valhalla or FakeValhalla(),
        flood=flood or FakeFlood(),
        weather=weather or FakeWeather(),
        events=FakeEvents(),
        explain=explain or FakeExplain(),
    )


def test_recommends_lower_exposure_when_the_detour_is_short():
    explain = FakeExplain()
    result = asyncio.run(plan_trip(
        TripRequest(origin=ORIGIN, destination=DEST, depart_at=datetime(2026, 10, 10, 18, tzinfo=MIAMI)),
        _services(explain=explain),
    ))
    assert result.recommended_id == "detour"
    fastest = next(route for route in result.routes if route.id == "fastest")
    avoided = next(route for route in result.routes if route.id == "detour")
    assert fastest.flood.intersecting is True
    assert fastest.flood.closure is False
    assert avoided.flood.intersecting is False
    assert result.flood_zones
    assert result.explanation is None
    assert "ticketmaster_unconfigured" in result.data_gaps
    note, gaps = asyncio.run(write_explanation(result.explanation_facts, explain))
    assert explain.facts["closure"] is False
    assert "not a road closure" in build_prompt(explain.facts)
    assert note.model == "gemma-4-26b-a4b-it"
    assert gaps == []


def test_keeps_fastest_when_the_detour_costs_more_than_the_flood_penalty():
    result = asyncio.run(plan_trip(
        TripRequest(origin=ORIGIN, destination=DEST),
        _services(valhalla=FakeValhalla(alternate_duration=800 + 40 * 60)),
    ))
    assert result.recommended_id == "fastest"


def test_missing_flood_data_still_returns_a_route():
    result = asyncio.run(plan_trip(
        TripRequest(origin=ORIGIN, destination=DEST),
        _services(flood=BrokenFlood(), explain=FakeExplain(api_key="")),
    ))
    assert result.routes[0].id == "fastest"
    assert result.recommended_id == "fastest"
    assert "flood_zones_unavailable" in result.data_gaps
    assert "gemini_unconfigured" not in result.data_gaps
    assert result.explanation is None
    note, gaps = asyncio.run(write_explanation(result.explanation_facts, FakeExplain(api_key="")))
    assert note.model == "route-scores"
    assert "could not be loaded" in note.text
    assert gaps == []


def test_avoidance_failure_is_a_data_gap():
    result = asyncio.run(plan_trip(
        TripRequest(origin=ORIGIN, destination=DEST),
        _services(valhalla=FakeValhalla(fail_avoid=True)),
    ))
    assert [route.id for route in result.routes] == ["fastest"]
    assert "valhalla_avoid_failed" in result.data_gaps


def test_rejects_points_outside_south_florida():
    from app.planning import OutsideArea

    with pytest.raises(OutsideArea):
        asyncio.run(plan_trip(
            TripRequest(origin=Place(label="Orlando", lat=28.5, lng=-81.3), destination=DEST),
            _services(),
        ))


def test_hides_flood_zones_without_an_active_alert():
    valhalla = FakeValhalla()
    result = asyncio.run(plan_trip(
        TripRequest(origin=ORIGIN, destination=DEST),
        _services(valhalla=valhalla, weather=CalmWeather()),
    ))
    assert result.weather is not None
    assert result.weather.flood_active is False
    assert result.flood_zones == []
    assert result.routes[0].flood.intersecting is False
    assert "No active flood alert" in result.routes[0].flood.summary
    assert [route.id for route in result.routes] == ["fastest"]
    assert valhalla.exclude_calls == 0


def test_flood_watch_is_not_treated_as_active_flooding():
    from app.services.weather import is_active_flood

    assert is_active_flood("Flood Warning")
    assert is_active_flood("Flash Flood Warning")
    assert is_active_flood("Coastal Flood Advisory")
    assert not is_active_flood("Flood Watch")
    assert not is_active_flood("Flash Flood Watch")
    assert not is_active_flood("Heat Advisory")
    assert not is_active_flood("Hydrologic Outlook")
    assert not is_active_flood("Coastal Flood Statement")


def test_score_and_prompt_do_not_invent_a_closure():
    scored = score_route(800, 1, 100, 0)
    assert scored["total_seconds"] > scored["duration_seconds"]
    assert scored["weights"] == WEIGHTS
    facts = explanation_facts("fastest", [{"id": "fastest", "closure": False}], [], [])
    prompt = build_prompt(facts)
    assert "not a road closure" in prompt
    assert "will not affect this ride" in prompt
    assert facts["closure"] is False
    assert facts["flood_active"] is False


def test_later_events_are_named_and_do_not_affect_the_ride():
    depart = datetime(2026, 10, 10, 12, 40, tzinfo=MIAMI)
    tonight = datetime(2026, 10, 10, 19, 30, tzinfo=MIAMI)
    tomorrow = datetime(2026, 10, 11, 20, 0, tzinfo=MIAMI)
    assert _event_when(tonight.isoformat(), depart) == "later tonight at 7:30 PM"
    assert _event_when(tomorrow.isoformat(), depart) == "tomorrow at 8:00 PM"
    facts = explanation_facts(
        "fastest",
        [
            {
                "id": "fastest",
                "label": "Fastest drive",
                "duration_minutes": 13.8,
                "distance_km": 14.58,
                "events_on_route": [
                    {
                        "name": "The French Horn Collective",
                        "venue": "Thomson Plaza for the Arts",
                        "when": "later tonight at 7:30 PM",
                        "affects_this_ride": False,
                    }
                ],
            }
        ],
        [],
        [],
    )
    text = explain_from_facts(facts)
    assert "The French Horn Collective at Thomson Plaza for the Arts is later tonight at 7:30 PM" in text
    assert "will not affect this ride" in text
    short = "The fastest drive is the recommended route with a score of 825.3 seconds."
    filled = with_later_events(short, facts)
    assert short in filled
    assert "will not affect this ride" in filled
    assert filled == with_later_events(filled, facts)
