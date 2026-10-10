import json
from dataclasses import dataclass

import httpx

from app.cache import SqliteCache
from app.geo import exterior_ring, polygon_from_geojson

FLOOD_QUERY = "https://gisweb.miamidade.gov/arcgis/rest/services/MD_Emaps/MapServer/85/query"
FLOOD_SOURCE = "Miami-Dade GIS MD_Emaps layer 85 (FEMA flood zones)"


@dataclass
class FloodZone:
    id: str
    zone: str
    subtype: str | None
    geometry: object

    @property
    def ring(self) -> list[list[float]]:
        return exterior_ring(self.geometry)


class FloodError(Exception):
    pass


class FloodClient:
    def __init__(self, client: httpx.AsyncClient, cache: SqliteCache):
        self.client = client
        self.cache = cache

    async def zones_in_bbox(
        self, min_lng: float, min_lat: float, max_lng: float, max_lat: float
    ) -> tuple[list[FloodZone], list[str]]:
        gaps: list[str] = []
        features: list[dict] = []
        offset = 0
        truncated = False
        while offset < 200:
            page, exceeded = await self._page(min_lng, min_lat, max_lng, max_lat, offset)
            features.extend(page)
            if not exceeded or not page:
                break
            truncated = True
            offset += len(page)
        if truncated:
            gaps.append("flood_zones_truncated")
        zones: list[FloodZone] = []
        for feature in features:
            props = feature.get("properties") or {}
            zone_code = str(props.get("FZONE") or "").strip().upper()
            if not zone_code.startswith(("A", "V")):
                continue
            geometry = polygon_from_geojson(feature.get("geometry") or {})
            if geometry is None:
                continue
            subtype = str(props.get("ZONESUBTY") or "").strip() or None
            zones.append(
                FloodZone(
                    id=f"md-{props.get('OBJECTID') or len(zones)}",
                    zone=zone_code,
                    subtype=subtype,
                    geometry=geometry,
                )
            )
        return zones, gaps

    async def _page(
        self, min_lng: float, min_lat: float, max_lng: float, max_lat: float, offset: int
    ) -> tuple[list[dict], bool]:
        key = f"flood:{min_lng:.3f}:{min_lat:.3f}:{max_lng:.3f}:{max_lat:.3f}:{offset}"
        cached = self.cache.get(key)
        if cached:
            payload = json.loads(cached)
            return payload["features"], payload["exceeded"]
        params = {
            "where": "(FZONE LIKE 'A%' OR FZONE LIKE 'V%')",
            "geometry": json.dumps(
                {
                    "xmin": min_lng,
                    "ymin": min_lat,
                    "xmax": max_lng,
                    "ymax": max_lat,
                    "spatialReference": {"wkid": 4326},
                }
            ),
            "geometryType": "esriGeometryEnvelope",
            "inSR": "4326",
            "spatialRel": "esriSpatialRelIntersects",
            "outFields": "OBJECTID,FZONE,ZONESUBTY",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
            "resultRecordCount": "100",
            "resultOffset": str(offset),
            "maxAllowableOffset": "0.0007",
            "geometryPrecision": "5",
        }
        try:
            response = await self.client.get(FLOOD_QUERY, params=params, timeout=25)
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise FloodError("Flood-zone polygons could not be loaded.") from exc
        if payload.get("error"):
            raise FloodError("Flood-zone polygons could not be loaded.")
        features = payload.get("features") or []
        exceeded = bool(payload.get("exceededTransferLimit"))
        self.cache.set(key, json.dumps({"features": features, "exceeded": exceeded}), 60 * 30)
        return features, exceeded
