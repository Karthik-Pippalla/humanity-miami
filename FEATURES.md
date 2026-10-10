# How Survive Miami works

Survive Miami is a South Florida driving and safety app. It compares a normal drive with one that reduces exposure to mapped flood zones and scheduled events, shows official weather alerts, builds a personal storm checklist, finds nearby emergency resources, and plans a timed Miami day.

The same FastAPI service backs three clients:

- The website (`web/`) draws the map with Google Maps and calls the API on port 8000.
- The iPhone app (`ios/MapMiami`) uses the same modes: Drive, Alerts, Prepare, and Plan Miami. A debug build talks to `http://127.0.0.1:8000`. A release build uses the hosted site.
- Apple Watch and the Home Screen widgets show the downtown Miami flood snapshot only. They do not plan routes or days.

Routes stay inside South Florida (about latitude 25.2–26.45 and longitude −80.95 to −79.85). A point outside that box is rejected.

## What the model is allowed to do

Gemma 4 (`gemma-4-26b-a4b-it`) writes explanations and chooses among results the app already computed. It does not invent drive times, flood maps, alert headlines, hospital addresses, or attraction locations.

If Gemma does not answer, the app still returns a result:

- Route text falls back to a sentence built from the scores.
- The checklist falls back to a fixed water, medicine, power, and go-bag list.
- Plan Miami falls back to the top matching places in the attraction catalog.

Official National Weather Service headlines stay in English. Gemma’s other text is labeled an explanation, not an official translation. Languages are English, Spanish, and Haitian Creole.

## Drive

You pick a start, a destination, and an optional departure time. A time with no timezone is read as Miami local time. The sample trip is Calle Ocho in Little Havana to the Miami Beach Convention Center.

1. Valhalla returns the fastest drive and its turn instructions.
2. The API asks the National Weather Service for alerts near the midpoint of that drive, and Ticketmaster for nearby events when a key is set.
3. Flood polygons are loaded only while a flood **warning or advisory** is active. A watch, outlook, or statement does not turn them on. The polygons are Miami-Dade FEMA special flood hazard areas. Crossing one is estimated exposure. The app has no road-closure feed, so it never marks a road as closed.
4. If the fastest line crosses a flood zone or an event that is happening at departure time, Valhalla is asked for a second route that avoids short stretches of that overlap.
5. Each route gets a score. The lower score is recommended. That can still be the fastest drive when the detour costs more than it saves.

The score starts with the typical drive time from Valhalla. That time is not live traffic. Then it adds:

- 3 minutes for each mapped flood zone the line crosses, plus 0.15 seconds per meter of overlap.
- 8 minutes for each event whose venue the line crosses and whose window includes the departure time.

Google Maps only draws the lines, flood rings, and event rings. On iPhone, the chosen route can open a navigation preview with those maneuvers. CarPlay can show the two routes and the exposure summary. It does not speak turn-by-turn guidance. Apple has to grant the CarPlay maps entitlement before a car can show that scene. See `ios/CARPLAY.md`.

## Alerts

Alerts are official National Weather Service products for a point you choose, or for downtown Miami when no point is sent. Watch and widgets always use downtown Miami so they keep working without a GPS fix.

Each alert is grouped as hurricane (including tropical storm, tropical depression, and storm surge), heavy rain (flash flood, heavy rain, excessive rainfall), flood, or storm (thunderstorm, tornado, marine, high wind, wind advisory, gale). A product whose title contains “watch” or “outlook” is marked as a watch. `flood_active` is true only for a flood warning or advisory, not a watch, outlook, or statement.

Spanish and Haitian Creole add a Gemma explanation under the English headline. The headline itself is not rewritten.

## Prepare

Prepare has two parts.

**Build checklist** takes household notes: how many people, pets, mobility, medical needs, and free text. The API loads NWS headlines for the chosen point, then asks Gemma for a short checklist tied to those headlines and notes. Each item has a category, an action, and a reason. The notice on the response says this is not an official emergency order.

**Nearby help** uses a checked-in list of Miami-Dade hospitals, emergency management, shelter information, and the Red Cross. Needs such as wheelchair, elderly, or medical filter that list. The app ranks matches by straight-line distance, then asks Valhalla for a drive time and keeps the closest few. “No car” asks for a walking time instead. Every card says to confirm the site is open. Shelter status changes during an emergency, and this list is not a live shelter assignment.

## Plan Miami

Plan Miami asks for age, interests, budget, vibe, accessibility needs, a start point, and an optional day. Gemma may only pick stops from the checked-in attraction catalog (museums, parks, neighborhoods, and similar places in `backend/app/data/miami_attractions.json`).

The model can search that catalog, ask for one drive leg, or ask for weather at a stop. It tries native tool calls first. If the model rejects tools, the same choices run as a JSON action loop, up to six steps and four stops. Unknown stop ids are dropped.

After the model finishes, the API throws away the model’s clock and recomputes it:

1. The first stop’s arrival is the start time plus the real drive from your start point.
2. Departure from a stop is arrival plus that place’s catalog dwell time.
3. The next arrival is that departure plus the next drive.

Drive times prefer Google Routes with traffic awareness when `GOOGLE_MAPS_API_KEY` works. Otherwise they are a Valhalla typical drive for that time of day, and the response says live traffic was unavailable.

Wheelchair need keeps only wheelchair-accessible catalog places. Age 65 or an elderly need keeps places marked low-walking or wheelchair-accessible. Budget drops places above the chosen level (free, low, medium, high).

## Data the app names when something is missing

| Gap | Meaning |
| --- | --- |
| `weather_unavailable` | NWS could not be read |
| `events_unavailable` | Ticketmaster could not be read |
| `flood_zones_unavailable` | Flood polygons could not be loaded |
| `valhalla_avoid_failed` | The detour request failed; only the fastest drive is returned |
| `live_traffic_unavailable` | Plan Miami used a typical drive time |
| `routing_unavailable` | A nearby-help drive time was estimated from distance |
| `gemini_unavailable` | Gemma did not answer; a fallback was used |
| `planner_adjusted` | A model stop was dropped or the catalog filled an empty day |

## API

| Method | Path | What it does |
| --- | --- | --- |
| GET | `/api/health` | Process is up |
| GET | `/api/alerts` | Alerts for downtown Miami, or for `lat` and `lng` together |
| GET | `/api/geocode?q=` | Server geocoder |
| POST | `/api/routes` | Compare the fastest drive and an optional avoidance detour |
| POST | `/api/explain` | Rewrite route facts in the chosen language |
| POST | `/api/prepare` | Storm checklist from alerts and household notes |
| POST | `/api/assist` | Nearby emergency resources and short steps |
| POST | `/api/plan` | Timed day from the attraction catalog |

Sources: Valhalla, Miami-Dade GIS FEMA flood zones, National Weather Service, Ticketmaster Discovery, Google Routes for Plan Miami traffic, Gemini API for Gemma 4, Google Maps for the basemap.
