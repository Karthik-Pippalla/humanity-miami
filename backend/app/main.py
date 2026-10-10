from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.alerts import alerts_for, city_alerts
from app.cache import SqliteCache
from app.config import settings
from app.geo import in_south_florida
from app.planning import OutsideArea, Services, plan_trip, write_explanation
from app.schemas import (
    AlertsOut,
    AssistRequest,
    AssistResponse,
    ExplainRequest,
    ExplainResponse,
    GeocodeResult,
    PlanRequest,
    PlanResponse,
    PrepareRequest,
    PrepareResponse,
    TripRequest,
    TripResponse,
)
from app.services.assistant import assist, prepare_checklist, translate_advisories
from app.services.events import EventClient
from app.services.explain import ExplainClient
from app.services.flood import FloodClient
from app.services.geocode import GeocodeClient, GeocodeError
from app.services.languages import normalize_language
from app.services.planner_agent import plan_itinerary
from app.services.traffic import TrafficClient
from app.services.valhalla import ValhallaClient, ValhallaError
from app.services.weather import WeatherClient


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with httpx.AsyncClient(
        timeout=30,
        follow_redirects=True,
        headers={"User-Agent": settings.nws_user_agent},
    ) as client:
        cache = SqliteCache(settings.cache_path)
        app.state.services = Services(
            valhalla=ValhallaClient(settings.valhalla_url, client),
            flood=FloodClient(client, cache),
            weather=WeatherClient(client),
            events=EventClient(client, settings.ticketmaster_api_key),
            explain=ExplainClient(settings.gemini_api_key, settings.gemma_model),
        )
        app.state.geocoder = GeocodeClient(client, settings.google_maps_api_key)
        app.state.http = client
        yield


app = FastAPI(title="Survive Miami", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list or ["http://localhost:5173"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict:
    return {"ok": True, "service": "map-miami", "routing": "valhalla", "map": "google-maps"}


@app.get("/api/alerts", response_model=AlertsOut)
async def alerts(lat: float | None = None, lng: float | None = None, language: str = "en") -> AlertsOut:
    if (lat is None) ^ (lng is None):
        raise HTTPException(status_code=400, detail="Provide both lat and lng, or neither.")
    try:
        if lat is None or lng is None:
            payload = await city_alerts(app.state.services.weather)
        else:
            payload = await alerts_for(app.state.services.weather, lat, lng, "Your location")
    except Exception as exc:
        raise HTTPException(status_code=503, detail="weather_unavailable") from exc
    return await translate_advisories(payload, normalize_language(language), app.state.services.explain)


@app.get("/api/geocode", response_model=list[GeocodeResult])
async def geocode(q: str) -> list[GeocodeResult]:
    query = q.strip()
    if len(query) < 3:
        return []
    try:
        return await app.state.geocoder.search(query)
    except GeocodeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/api/routes", response_model=TripResponse)
async def routes(body: TripRequest) -> TripResponse:
    try:
        return await plan_trip(body, app.state.services)
    except OutsideArea as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except ValhallaError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.post("/api/explain", response_model=ExplainResponse)
async def explain(body: ExplainRequest) -> ExplainResponse:
    explanation, gaps = await write_explanation(
        body.facts, app.state.services.explain, normalize_language(body.language)
    )
    return ExplainResponse(explanation=explanation, data_gaps=gaps)


def _local(place) -> None:
    if place is None or not in_south_florida(place.lat, place.lng):
        raise OutsideArea("Choose a point in South Florida.")


@app.post("/api/prepare", response_model=PrepareResponse)
async def prepare(body: PrepareRequest) -> PrepareResponse:
    try:
        if body.location is not None:
            _local(body.location)
    except OutsideArea as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return await prepare_checklist(body, app.state.services.weather, app.state.services.explain)


@app.post("/api/assist", response_model=AssistResponse)
async def assist_route(body: AssistRequest) -> AssistResponse:
    try:
        _local(body.location)
    except OutsideArea as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return await assist(body, app.state.services.weather, app.state.services.valhalla, app.state.services.explain)


@app.post("/api/plan", response_model=PlanResponse)
async def plan(body: PlanRequest) -> PlanResponse:
    try:
        _local(body.start)
    except OutsideArea as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    traffic = TrafficClient(app.state.http, settings.google_maps_api_key, app.state.services.valhalla)
    return await plan_itinerary(body, traffic, app.state.services.weather, app.state.services.explain)
