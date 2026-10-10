import math

import pytest
from shapely.geometry import LineString, Polygon, box

from app.geo import avoidance_rings, avoid_ring, corridor_slice, decode_polyline, hits_along, length_meters


def _encode(coords: list[tuple[float, float]], precision: int = 6) -> str:
    scale = 10**precision
    output: list[str] = []
    prev_lat = prev_lng = 0
    for lat, lng in coords:
        for value, prev in ((lat, prev_lat), (lng, prev_lng)):
            delta = int(round(value * scale)) - int(round(prev * scale))
            shifted = ~(delta << 1) if delta < 0 else delta << 1
            while shifted >= 0x20:
                output.append(chr((0x20 | (shifted & 0x1F)) + 63))
                shifted >>= 5
            output.append(chr(shifted + 63))
            if prev is prev_lat and value == lat:
                prev_lat = lat
            else:
                prev_lng = lng
    return "".join(output)


def test_polyline_roundtrip_precision_6():
    coords = [(25.765376, -80.219871), (25.7701, -80.18), (25.790693, -80.129994)]
    decoded = decode_polyline(_encode(coords), 6)
    assert len(decoded) == 3
    for original, result in zip(coords, decoded):
        assert result[0] == pytest.approx(original[0], abs=1e-6)
        assert result[1] == pytest.approx(original[1], abs=1e-6)


def test_hits_ignore_a_mere_touch():
    line = LineString([(-80.30, 25.70), (-80.10, 25.70)])
    beside = box(-80.22, 25.71, -80.18, 25.74)
    across = box(-80.22, 25.69, -80.18, 25.72)
    hits = hits_along(line, [("beside", beside), ("across", across)])
    assert [hit.zone_id for hit in hits] == ["across"]
    assert hits[0].overlap_meters > 25


def test_corridor_slice_stays_near_the_road():
    line = LineString([(-80.22, 25.76), (-80.13, 25.79)])
    wide = box(-80.30, 25.50, -80.05, 25.90)
    piece = corridor_slice(line, wide, radius_m=160)
    assert piece is not None
    ring = avoid_ring(piece)
    assert len(ring) >= 4
    assert ring[0] == ring[-1]
    # The avoidance shape should not swallow the whole county-sized zone.
    assert piece.area < wide.area / 10
    assert length_meters(line.intersection(piece)) > 100


def test_avoidance_rings_stay_under_valhalla_limit():
    line = LineString([(-80.25, 25.75), (-80.10, 25.80)])
    wide = box(-80.30, 25.50, -80.05, 25.95)
    rings = avoidance_rings(line, wide, limit=4)
    assert rings
    for ring in rings:
        polygon = Polygon(ring)
        assert length_meters(polygon.exterior) < 9500
        assert ring[0] == ring[-1]


def test_length_is_roughly_metric():
    line = LineString([(-80.20, 25.76), (-80.20, 25.77)])
    # 0.01 degree of latitude is about 1.1 km.
    assert length_meters(line) == pytest.approx(1105, rel=0.05)
    assert math.isfinite(length_meters(Polygon(line.buffer(0.001))))
