import httpx

from app.schemas import GeocodeResult


class GeocodeError(Exception):
    pass


class GeocodeClient:
    def __init__(self, client: httpx.AsyncClient, api_key: str):
        self.client = client
        self.api_key = api_key

    async def search(self, query: str) -> list[GeocodeResult]:
        if not self.api_key:
            raise GeocodeError("Google geocoding is not configured.")
        response = await self.client.get(
            "https://maps.googleapis.com/maps/api/geocode/json",
            params={
                "address": query,
                "key": self.api_key,
                "components": "country:US",
                "bounds": "25.40,-80.70|26.05,-80.00",
            },
            timeout=15,
        )
        response.raise_for_status()
        payload = response.json()
        status = payload.get("status")
        if status not in {"OK", "ZERO_RESULTS"}:
            raise GeocodeError(payload.get("error_message") or "Geocoding failed.")
        results: list[GeocodeResult] = []
        for item in payload.get("results") or []:
            location = (item.get("geometry") or {}).get("location") or {}
            try:
                lat = float(location["lat"])
                lng = float(location["lng"])
            except (KeyError, TypeError, ValueError):
                continue
            if not (25.2 <= lat <= 26.45 and -80.95 <= lng <= -79.85):
                continue
            label = item.get("formatted_address")
            if label:
                results.append(GeocodeResult(label=label, lat=lat, lng=lng))
        return results[:5]
