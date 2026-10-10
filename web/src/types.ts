export type Place = {
  label: string;
  lat: number;
  lng: number;
};

export type ScoreBreakdown = {
  duration_seconds: number;
  flood_zone_count: number;
  flood_overlap_meters: number;
  events_in_window: number;
  flood_penalty_seconds: number;
  event_penalty_seconds: number;
  total_seconds: number;
};

export type RouteCandidate = {
  id: string;
  label: string;
  geometry: { type: "LineString"; coordinates: number[][] };
  duration_seconds: number;
  distance_meters: number;
  has_toll: boolean;
  flood: {
    estimated_risk: boolean;
    closure: boolean;
    intersecting: boolean;
    zone_ids: string[];
    overlap_meters: number;
    summary: string;
  };
  events: {
    id: string;
    name: string;
    venue: string;
    start: string | null;
    intersects_route: boolean;
    in_departure_window: boolean;
  }[];
  score: ScoreBreakdown;
};

export type TripResponse = {
  origin: Place;
  destination: Place;
  recommended_id: string;
  routes: RouteCandidate[];
  flood_zones: { id: string; zone: string; subtype: string | null; ring: number[][] }[];
  event_zones: {
    id: string;
    name: string;
    venue: string;
    start: string | null;
    ring: number[][];
    intersects_route: boolean;
    in_departure_window: boolean;
  }[];
  weather: { forecast: string | null; temperature_f: number | null; alerts: string[]; flood_active: boolean } | null;
  explanation: { text: string; model: string } | null;
  explanation_facts: Record<string, unknown>;
  data_gaps: string[];
  notice: string;
};

export type Explanation = {
  text: string;
  model: string;
};

export type Language = "en" | "es" | "ht";

export type Advisory = {
  event: string;
  headline: string;
  severity: string | null;
  urgency: string | null;
  instruction: string | null;
  onset: string | null;
  ends: string | null;
  category: string;
  is_watch: boolean;
  plain_language: string | null;
};

export type AlertsResponse = {
  place: string;
  forecast: string | null;
  temperature_f: number | null;
  alerts: string[];
  flood_active: boolean;
  notice: string;
  advisories: Advisory[];
  language: string;
  data_gaps: string[];
};

export type ChecklistItem = {
  category: string;
  action: string;
  why: string;
};

export type PrepareResponse = {
  items: ChecklistItem[];
  model: string;
  language: string;
  alerts: string[];
  data_gaps: string[];
  notice: string;
};

export type ResourceCard = {
  id: string;
  name: string;
  kind: string;
  address: string;
  lat: number;
  lng: number;
  serves: string[];
  source_url: string;
  drive_minutes: number | null;
  distance_meters: number | null;
  estimated: boolean;
  confirm: string;
};

export type AssistResponse = {
  resources: ResourceCard[];
  steps: ChecklistItem[];
  model: string;
  language: string;
  alerts: string[];
  data_gaps: string[];
  notice: string;
};

export type ItineraryStop = {
  id: string;
  name: string;
  lat: number;
  lng: number;
  arrival: string;
  dwell_minutes: number;
  leave: string;
  travel_minutes: number | null;
  why: string;
};

export type PlanResponse = {
  stops: ItineraryStop[];
  geometry: { type: "LineString"; coordinates: number[][] };
  note: string;
  model: string;
  timing_source: string;
  language: string;
  data_gaps: string[];
  notice: string;
};

export const DEMO = {
  origin: { label: "Calle Ocho, Little Havana", lat: 25.7653, lng: -80.2196 },
  destination: { label: "Miami Beach Convention Center", lat: 25.7907, lng: -80.13 },
};

export const GAP_COPY: Record<string, string> = {
  ticketmaster_unconfigured: "Event listings need a Ticketmaster API key.",
  gemini_unavailable: "Gemma 4 did not respond, so this uses the built-in note.",
  flood_zones_unavailable: "Flood-zone polygons could not be loaded, so exposure was not scored.",
  flood_zones_truncated: "Only part of the flood-zone layer was returned for this area.",
  weather_unavailable: "National Weather Service data could not be loaded.",
  valhalla_avoid_failed: "A route that avoids the exposed stretches could not be calculated.",
  events_unavailable: "Event listings could not be loaded.",
  live_traffic_unavailable: "Live traffic was unavailable, so times are a typical drive for that time of day.",
  routing_unavailable: "A drive time could not be calculated for every stop.",
  planner_adjusted: "A place that was not in the Miami catalog was left out of the plan.",
};
