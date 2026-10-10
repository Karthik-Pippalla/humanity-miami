import math
from dataclasses import dataclass

import numpy as np
from shapely import transform
from shapely.geometry import GeometryCollection, LineString, MultiLineString, MultiPolygon, Polygon, shape
from shapely.geometry.base import BaseGeometry
from shapely.ops import substring

LAT0 = 25.78
LON_SCALE = 111320 * math.cos(math.radians(LAT0))
LAT_SCALE = 110540

SOUTH_FLORIDA = (25.2, 26.45, -80.95, -79.85)


def in_south_florida(lat: float, lng: float) -> bool:
    south, north, west, east = SOUTH_FLORIDA
    return south <= lat <= north and west <= lng <= east


def decode_polyline(encoded: str, precision: int = 6) -> list[tuple[float, float]]:
    """Decode a Valhalla polyline into (lat, lng) pairs. Valhalla uses precision 6."""
    scale = 10**precision
    lat = lng = 0
    coords: list[tuple[float, float]] = []
    index = 0
    length = len(encoded)
    while index < length:
        for axis in range(2):
            shift = result = 0
            while True:
                if index >= length:
                    raise ValueError("Truncated polyline")
                chunk = ord(encoded[index]) - 63
                index += 1
                result |= (chunk & 0x1F) << shift
                shift += 5
                if chunk < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if axis == 0:
                lat += delta
            else:
                lng += delta
        coords.append((lat / scale, lng / scale))
    return coords


def to_meters(geom: BaseGeometry) -> BaseGeometry:
    return transform(geom, lambda coords: coords * np.array([LON_SCALE, LAT_SCALE]))


def from_meters(geom: BaseGeometry) -> BaseGeometry:
    return transform(geom, lambda coords: coords / np.array([LON_SCALE, LAT_SCALE]))


def length_meters(geom: BaseGeometry) -> float:
    if geom.is_empty:
        return 0.0
    return float(to_meters(geom).length)


def line_from_latlng(coords: list[tuple[float, float]]) -> LineString:
    return LineString([(lng, lat) for lat, lng in coords])


def geojson_line(line: LineString) -> dict:
    return {"type": "LineString", "coordinates": [[x, y] for x, y in line.coords]}


def circle_ring(lng: float, lat: float, radius_m: float, steps: int = 16) -> list[list[float]]:
    ring: list[list[float]] = []
    for step in range(steps):
        angle = 2 * math.pi * step / steps
        east = math.cos(angle) * radius_m
        north = math.sin(angle) * radius_m
        ring.append([round(lng + east / LON_SCALE, 6), round(lat + north / LAT_SCALE, 6)])
    ring.append(ring[0])
    return ring


def polygon_from_geojson(geometry: dict) -> Polygon | MultiPolygon | None:
    geom = shape(geometry)
    if isinstance(geom, (Polygon, MultiPolygon)):
        if not geom.is_valid:
            geom = geom.buffer(0)
        if geom.is_empty:
            return None
        return geom
    return None


def largest_polygon(geom: BaseGeometry) -> Polygon | None:
    if geom.is_empty:
        return None
    if isinstance(geom, Polygon):
        return geom
    if isinstance(geom, MultiPolygon):
        parts = [part for part in geom.geoms if not part.is_empty]
        return max(parts, key=lambda part: part.area) if parts else None
    if hasattr(geom, "geoms"):
        parts = [part for part in geom.geoms if isinstance(part, Polygon) and not part.is_empty]
        return max(parts, key=lambda part: part.area) if parts else None
    return None


def closed_ring(coords: list[tuple[float, float]], limit: int = 18) -> list[list[float]]:
    ring = [[round(x, 5), round(y, 5)] for x, y in coords]
    cleaned: list[list[float]] = []
    for point in ring:
        if not cleaned or point != cleaned[-1]:
            cleaned.append(point)
    if len(cleaned) >= 2 and cleaned[0] != cleaned[-1]:
        cleaned.append(cleaned[0])
    if len(cleaned) < 4:
        return []
    if len(cleaned) <= limit:
        return cleaned
    # Keep evenly spaced vertices and close the ring.
    body = cleaned[:-1]
    step = max(1, math.ceil(len(body) / (limit - 1)))
    reduced = body[::step]
    if reduced[-1] != body[-1]:
        reduced.append(body[-1])
    if reduced[0] != reduced[-1]:
        reduced.append(reduced[0])
    return reduced if len(reduced) >= 4 else []


def avoid_ring(polygon: Polygon) -> list[list[float]]:
    simplified = polygon.simplify(0.00035, preserve_topology=True)
    target = largest_polygon(simplified) or polygon
    if target.exterior is None:
        return []
    return closed_ring(list(target.exterior.coords))


def _line_parts(geom: BaseGeometry) -> list[LineString]:
    if isinstance(geom, LineString):
        return [] if geom.is_empty else [geom]
    if isinstance(geom, (MultiLineString, GeometryCollection)):
        parts: list[LineString] = []
        for child in geom.geoms:
            parts.extend(_line_parts(child))
        return parts
    return []


def split_line_meters(line: LineString, chunk_m: float) -> list[LineString]:
    local = to_meters(line)
    total = float(local.length)
    if total < 30:
        return []
    pieces: list[LineString] = []
    start = 0.0
    while start < total - 1:
        end = min(total, start + chunk_m)
        piece = substring(local, start, end)
        if not piece.is_empty and float(piece.length) >= 30:
            restored = from_meters(piece)
            if isinstance(restored, LineString):
                pieces.append(restored)
        start = end
    return pieces


def avoidance_rings(
    line: LineString,
    zone: BaseGeometry,
    radius_m: float = 80,
    chunk_m: float = 900,
    limit: int = 3,
) -> list[list[list[float]]]:
    """Small avoid polygons. Public Valhalla rejects an exclude ring longer than 10 km."""
    rings: list[list[list[float]]] = []
    for part in _line_parts(line.intersection(zone)):
        for chunk in split_line_meters(part, chunk_m):
            polygon = largest_polygon(from_meters(to_meters(chunk).buffer(radius_m)))
            if polygon is None:
                continue
            if length_meters(polygon.exterior) > 9500:
                continue
            ring = avoid_ring(polygon)
            if ring:
                rings.append(ring)
            if len(rings) >= limit:
                return rings
    return rings


def corridor_slice(line: LineString, zone: BaseGeometry, radius_m: float = 160) -> Polygon | None:
    """Portion of a flood zone within a corridor of the route, as an avoidance polygon."""
    corridor = from_meters(to_meters(line).buffer(radius_m))
    piece = zone.intersection(corridor)
    if piece.is_empty:
        return None
    polygon = largest_polygon(piece)
    if polygon is None or polygon.area <= 0:
        polygon = largest_polygon(piece.buffer(0.0002))
    if polygon is None or polygon.is_empty:
        return None
    return polygon


def exterior_ring(zone: BaseGeometry) -> list[list[float]]:
    polygon = largest_polygon(zone)
    if polygon is None:
        return []
    simplified = polygon.simplify(0.00045, preserve_topology=True)
    target = largest_polygon(simplified) or polygon
    return closed_ring(list(target.exterior.coords), limit=48)


@dataclass
class MeasuredHit:
    zone_id: str
    overlap_meters: float
    geometry: BaseGeometry


def hits_along(line: LineString, zones: list[tuple[str, BaseGeometry]], minimum_m: float = 25) -> list[MeasuredHit]:
    found: list[MeasuredHit] = []
    for zone_id, geom in zones:
        overlap = length_meters(line.intersection(geom))
        if overlap >= minimum_m:
            found.append(MeasuredHit(zone_id, overlap, geom))
    return found


def bbox_of_line(line: LineString, pad: float = 0.04) -> tuple[float, float, float, float]:
    min_x, min_y, max_x, max_y = line.bounds
    return min_x - pad, min_y - pad, max_x + pad, max_y + pad


def point_in_window(depart, start, end) -> bool:
    if start is None:
        return False
    finish = end or start
    return start <= depart <= finish
