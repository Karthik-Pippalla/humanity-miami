from datetime import datetime

from pydantic import BaseModel, Field


class Place(BaseModel):
    label: str = Field(min_length=1, max_length=240)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class TripRequest(BaseModel):
    origin: Place
    destination: Place
    depart_at: datetime | None = None


class ScoreBreakdown(BaseModel):
    duration_seconds: float
    flood_zone_count: int
    flood_overlap_meters: float
    events_in_window: int
    flood_penalty_seconds: float
    event_penalty_seconds: float
    total_seconds: float
    weights: dict[str, float | str]


class FloodExposure(BaseModel):
    estimated_risk: bool = True
    closure: bool = False
    intersecting: bool
    zone_ids: list[str]
    overlap_meters: float
    summary: str


class EventHit(BaseModel):
    id: str
    name: str
    venue: str
    start: str | None
    end: str | None
    intersects_route: bool
    in_departure_window: bool


class RouteManeuver(BaseModel):
    type: int
    instruction: str
    length_meters: float
    time_seconds: float
    begin_shape_index: int
    end_shape_index: int


class RouteCandidate(BaseModel):
    id: str
    label: str
    geometry: dict
    duration_seconds: float
    distance_meters: float
    has_toll: bool
    flood: FloodExposure
    events: list[EventHit]
    score: ScoreBreakdown
    maneuvers: list[RouteManeuver] = Field(default_factory=list)


class FloodZoneOut(BaseModel):
    id: str
    zone: str
    subtype: str | None
    ring: list[list[float]]


class EventZoneOut(BaseModel):
    id: str
    name: str
    venue: str
    start: str | None
    end: str | None
    ring: list[list[float]]
    intersects_route: bool
    in_departure_window: bool


class WeatherOut(BaseModel):
    forecast: str | None
    temperature_f: float | None
    alerts: list[str]
    flood_active: bool = False


class AdvisoryOut(BaseModel):
    event: str
    headline: str
    severity: str | None = None
    urgency: str | None = None
    instruction: str | None = None
    onset: str | None = None
    ends: str | None = None
    category: str
    is_watch: bool = False
    plain_language: str | None = None


class AlertsOut(BaseModel):
    place: str
    forecast: str | None
    temperature_f: float | None
    alerts: list[str]
    flood_active: bool
    notice: str
    advisories: list[AdvisoryOut] = Field(default_factory=list)
    lat: float | None = None
    lng: float | None = None
    language: str = "en"
    data_gaps: list[str] = Field(default_factory=list)


class ExplanationOut(BaseModel):
    text: str
    model: str
    based_on: str = "route_facts"


class TripResponse(BaseModel):
    origin: Place
    destination: Place
    recommended_id: str
    routes: list[RouteCandidate]
    flood_zones: list[FloodZoneOut]
    event_zones: list[EventZoneOut]
    weather: WeatherOut | None
    explanation: ExplanationOut | None = None
    explanation_facts: dict
    data_gaps: list[str]
    sources: dict[str, str | None]
    notice: str


class ExplainRequest(BaseModel):
    facts: dict
    language: str = "en"


class ChecklistItem(BaseModel):
    category: str
    action: str
    why: str


class PrepareRequest(BaseModel):
    location: Place | None = None
    notes: str = Field(default="", max_length=2000)
    people: int | None = Field(default=None, ge=1, le=20)
    pets: bool = False
    mobility: str = Field(default="", max_length=400)
    medical: str = Field(default="", max_length=400)
    language: str = "en"


class PrepareResponse(BaseModel):
    items: list[ChecklistItem]
    model: str
    language: str
    alerts: list[str]
    data_gaps: list[str]
    notice: str


class AssistRequest(BaseModel):
    location: Place
    needs: list[str] = Field(default_factory=list)
    language: str = "en"


class ResourceOut(BaseModel):
    id: str
    name: str
    kind: str
    address: str
    lat: float
    lng: float
    serves: list[str]
    source_url: str
    drive_minutes: float | None = None
    distance_meters: float | None = None
    estimated: bool = False
    confirm: str


class AssistResponse(BaseModel):
    resources: list[ResourceOut]
    steps: list[ChecklistItem]
    model: str
    language: str
    alerts: list[str]
    data_gaps: list[str]
    notice: str


class PlanRequest(BaseModel):
    age: int = Field(ge=1, le=120)
    interests: list[str] = Field(default_factory=list)
    budget: str = "medium"
    vibe: str = "relaxed"
    start: Place
    day: datetime | None = None
    language: str = "en"
    needs: list[str] = Field(default_factory=list)


class ItineraryStop(BaseModel):
    id: str
    name: str
    lat: float
    lng: float
    arrival: str
    dwell_minutes: int
    leave: str
    travel_minutes: float | None = None
    why: str


class PlanResponse(BaseModel):
    stops: list[ItineraryStop]
    geometry: dict
    note: str
    model: str
    timing_source: str
    language: str
    data_gaps: list[str]
    notice: str


class ExplainResponse(BaseModel):
    explanation: ExplanationOut
    data_gaps: list[str]


class GeocodeResult(BaseModel):
    label: str
    lat: float
    lng: float
