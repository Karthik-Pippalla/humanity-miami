import { useEffect, useRef } from "react";
import { Map, useMap } from "@vis.gl/react-google-maps";
import type { PlanResponse, TripResponse } from "../types";

type Props = {
  trip: TripResponse | null;
  selectedId: string | null;
  plan?: PlanResponse | null;
};

function pathFrom(ring: number[][]) {
  return ring.map(([lng, lat]) => ({ lat, lng }));
}

function Overlays({ trip, selectedId, plan }: Props) {
  const map = useMap();
  const fitted = useRef<TripResponse | PlanResponse | null>(null);

  useEffect(() => {
    if (!map) return;
    if (plan) {
      const drawn: google.maps.MVCObject[] = [];
      const bounds = new google.maps.LatLngBounds();
      const path = pathFrom(plan.geometry.coordinates);
      path.forEach((point) => bounds.extend(point));
      drawn.push(
        new google.maps.Polyline({
          map,
          path,
          strokeColor: "#F07850",
          strokeOpacity: 0.95,
          strokeWeight: 6,
          zIndex: 4,
          clickable: false,
        }),
      );
      plan.stops.forEach((stop, index) => {
        const marker = new google.maps.Marker({
          map,
          position: { lat: stop.lat, lng: stop.lng },
          label: String(index + 1),
          title: stop.name,
          zIndex: 5,
        });
        bounds.extend(marker.getPosition()!);
        drawn.push(marker);
      });
      if (fitted.current !== plan && !bounds.isEmpty()) {
        map.fitBounds(bounds, 72);
        fitted.current = plan;
      }
      return () => {
        drawn.forEach((item) => {
          if (item instanceof google.maps.Marker || item instanceof google.maps.Polyline) item.setMap(null);
        });
      };
    }
    if (!trip) return;
    const drawn: google.maps.MVCObject[] = [];
    const bounds = new google.maps.LatLngBounds();

    for (const zone of trip.flood_zones) {
      const polygon = new google.maps.Polygon({
        map,
        paths: pathFrom(zone.ring),
        strokeColor: zone.zone.startsWith("V") ? "#075985" : "#0284c7",
        strokeOpacity: 0.9,
        strokeWeight: 1,
        fillColor: zone.zone.startsWith("V") ? "#0369a1" : "#38bdf8",
        fillOpacity: 0.28,
        zIndex: 1,
        clickable: false,
      });
      drawn.push(polygon);
    }

    for (const zone of trip.event_zones) {
      if (!zone.intersects_route && !zone.in_departure_window) continue;
      const polygon = new google.maps.Polygon({
        map,
        paths: pathFrom(zone.ring),
        strokeColor: "#C4922A",
        strokeOpacity: 0.95,
        strokeWeight: 1,
        fillColor: "#E2B043",
        fillOpacity: 0.3,
        zIndex: 2,
        clickable: false,
      });
      drawn.push(polygon);
    }

    const ordered = [...trip.routes].sort((a, b) => (a.id === selectedId ? 1 : b.id === selectedId ? -1 : 0));
    for (const route of ordered) {
      const selected = route.id === selectedId;
      const path = pathFrom(route.geometry.coordinates);
      path.forEach((point) => bounds.extend(point));
      const line = new google.maps.Polyline({
        map,
        path,
        strokeColor: selected ? "#F07850" : "#94A3B8",
        strokeOpacity: selected ? 0.95 : 0.7,
        strokeWeight: selected ? 7 : 4,
        zIndex: selected ? 4 : 3,
        clickable: false,
      });
      drawn.push(line);
    }

    const originMarker = new google.maps.Marker({
      map,
      position: { lat: trip.origin.lat, lng: trip.origin.lng },
      label: "A",
      title: trip.origin.label,
      zIndex: 5,
    });
    const destinationMarker = new google.maps.Marker({
      map,
      position: { lat: trip.destination.lat, lng: trip.destination.lng },
      label: "B",
      title: trip.destination.label,
      zIndex: 5,
    });
    bounds.extend(originMarker.getPosition()!);
    bounds.extend(destinationMarker.getPosition()!);
    drawn.push(originMarker, destinationMarker);

    if (fitted.current !== trip) {
      map.fitBounds(bounds, 72);
      fitted.current = trip;
    }

    return () => {
      drawn.forEach((item) => {
        if (item instanceof google.maps.Marker || item instanceof google.maps.Polyline || item instanceof google.maps.Polygon) {
          item.setMap(null);
        }
      });
    };
  }, [map, trip, selectedId, plan]);

  return null;
}

export function MapView({ trip, selectedId, plan, apiKey }: Props & { apiKey: string }) {
  if (!apiKey) {
    return (
      <div className="flex h-full items-center justify-center bg-navy p-8 text-center text-white">
        <div className="max-w-sm">
          <p className="font-display text-2xl text-white">Google Maps key needed</p>
          <p className="mt-2 text-sm leading-6 text-white/80">
            Add <code className="rounded bg-white/10 px-1 text-coral">VITE_GOOGLE_MAPS_API_KEY</code> to the project{" "}
            <code className="rounded bg-white/10 px-1 text-coral">.env</code> file, then restart the site. Enable the Maps JavaScript
            API and Places API for that key.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="relative h-full">
      <Map
        defaultCenter={{ lat: 25.78, lng: -80.19 }}
        defaultZoom={12}
        gestureHandling="greedy"
        mapTypeControl={false}
        streetViewControl={false}
        fullscreenControl={false}
        style={{ width: "100%", height: "100%" }}
      >
        <Overlays trip={trip} selectedId={selectedId} plan={plan} />
      </Map>
      <div className="pointer-events-none absolute bottom-4 left-4 rounded-xl border border-white/10 bg-navy/95 px-3 py-2 text-xs text-white shadow-sm">
        <p className="flex items-center gap-2">
          <span className="inline-block h-1.5 w-6 rounded-full bg-coral" /> Recommended drive
        </p>
        <p className="mt-1 flex items-center gap-2">
          <span className="inline-block h-3 w-3 rounded-sm bg-sky-400/80" /> Mapped flood zone
        </p>
        <p className="mt-1 flex items-center gap-2">
          <span className="inline-block h-3 w-3 rounded-sm bg-amber" /> Event area
        </p>
      </div>
    </div>
  );
}
