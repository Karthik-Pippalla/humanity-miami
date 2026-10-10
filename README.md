# Survive Miami

A Miami driving site that compares a normal route with one that reduces exposure to mapped flood zones and scheduled events. Google Maps draws the map. Route geometry and avoidance are calculated by Valhalla, then scored in Python. Gemma 4 only explains those scores.

The iOS app is not in this version. The HTTP API is the contract for it later.

Flood areas are drawn only while the National Weather Service has an active flood warning or advisory. A flood watch does not turn them on. Those areas are estimated exposure. The app does not have a road-closure feed, so it never marks a road as closed.

## Demo

1. Copy `.env.example` to `.env` and set `VITE_GOOGLE_MAPS_API_KEY` (Maps JavaScript API and Places API).
2. Start the API and the site (two terminals).
3. Open http://localhost:5173 and choose **Demo**.
4. The sample trip is Calle Ocho in Little Havana to the Miami Beach Convention Center.

Without `GEMINI_API_KEY`, the site writes the route explanation from the calculated scores. Adding that key asks Gemma 4 (`gemma-4-26b-a4b-it`) to phrase the same facts. `TICKETMASTER_API_KEY` adds event listings. `GOOGLE_MAPS_API_KEY` is the server geocoder for a future client.

## Run locally

```bash
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements.txt
backend/.venv/bin/uvicorn app.main:app --app-dir backend --reload --port 8000
```

```bash
npm install --prefix web
npm run dev --prefix web
```

Tests:

```bash
backend/.venv/bin/pytest backend
```

## API

- `GET /api/health`
- `GET /api/alerts` — Miami flood flag, alert titles, and forecast, with no origin or destination
- `GET /api/geocode?q=`
- `POST /api/routes` with `origin`, `destination`, and optional `depart_at` (naive times are read as Miami local time)

The route response includes candidate lines, flood exposure, event exposure, a recommended id, data gaps, and an optional explanation. Score penalties are in the payload. A second route asks Valhalla to avoid short stretches where the fastest drive crosses a flood zone. The lower score is recommended, which can still be the fastest drive when the detour does not reduce exposure.

Sources: Valhalla, Miami-Dade GIS FEMA flood zones (`MD_Emaps` layer 85), National Weather Service, Ticketmaster Discovery, Gemini API.

## Firebase

Hosting is a Vite SPA. `/api/**` rewrites to Cloud Run service `map-miami-api` in `us-east1`. That needs the Blaze plan and a deployed service. Do not deploy until a Firebase project id is chosen.

```bash
docker build -t map-miami-api .
gcloud run deploy map-miami-api --source . --region us-east1
npm run build --prefix web
npx -y firebase-tools@latest deploy --only hosting
```

Set `GEMINI_API_KEY`, `TICKETMASTER_API_KEY`, `GOOGLE_MAPS_API_KEY`, and `VALHALLA_URL` on the Cloud Run service. Restrict the browser maps key to the Hosting domain.
