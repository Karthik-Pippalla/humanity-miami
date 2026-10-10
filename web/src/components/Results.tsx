import type { Explanation, RouteCandidate, TripResponse } from "../types";
import { GAP_COPY } from "../types";

function minutes(seconds: number): string {
  const total = Math.max(1, Math.round(seconds / 60));
  if (total < 60) return `${total} min`;
  const hours = Math.floor(total / 60);
  const rest = total % 60;
  return rest ? `${hours} hr ${rest} min` : `${hours} hr`;
}

function miles(meters: number): string {
  return `${(meters / 1609.344).toFixed(1)} mi`;
}

function RouteCard({
  route,
  recommended,
  selected,
  onSelect,
}: {
  route: RouteCandidate;
  recommended: boolean;
  selected: boolean;
  onSelect: () => void;
}) {
  const floodMinutes = Math.round(route.score.flood_penalty_seconds / 60);
  const eventMinutes = Math.round(route.score.event_penalty_seconds / 60);
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`w-full rounded-2xl border px-3 py-3 text-left ${
        selected ? "border-coral bg-foam text-ink" : "border-line bg-white text-ink"
      }`}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold">{route.label}</p>
          <p className="text-xs text-ink/60">{recommended ? "Recommended" : "Alternate"}</p>
        </div>
        <div className="text-right">
          <p className="font-display text-xl leading-none">{minutes(route.duration_seconds)}</p>
          <p className="mt-1 text-xs text-ink/60">{miles(route.distance_meters)}</p>
        </div>
      </div>
      <p className="mt-2 text-sm leading-5 text-ink/80">{route.flood.summary}</p>
      {route.events.length > 0 && (
        <ul className="mt-2 space-y-1 text-sm text-ink/80">
          {route.events.map((event) => (
            <li key={event.id}>
              {event.name} at {event.venue}
              {event.in_departure_window ? " overlaps this departure." : " is scheduled outside this departure window."}
            </li>
          ))}
        </ul>
      )}
      <p className="mt-2 text-xs text-ink/55">
        {route.has_toll ? "Includes a toll. " : ""}
        {floodMinutes || eventMinutes
          ? `Score adds ${floodMinutes} min of flood-zone exposure${
              eventMinutes ? ` and ${eventMinutes} min of event exposure` : ""
            }. Not a closure.`
          : "Not a road closure."}
      </p>
    </button>
  );
}

export function Results({
  trip,
  selectedId,
  onSelect,
  explaining,
  explanation,
  explainGaps,
}: {
  trip: TripResponse;
  selectedId: string | null;
  onSelect: (id: string) => void;
  explaining: boolean;
  explanation: Explanation | null;
  explainGaps: string[];
}) {
  return (
    <div className="space-y-3">
      {trip.weather && (
        <div className="rounded-2xl bg-white px-3 py-2 text-sm text-ink">
          <p className="font-medium">
            {trip.weather.forecast || "Weather loaded"}
            {trip.weather.temperature_f != null ? ` · ${Math.round(trip.weather.temperature_f)}°F` : ""}
          </p>
          {trip.weather.flood_active ? (
            <p className="text-coral">Active flood alert. Mapped flood areas along the route are shown in blue.</p>
          ) : (
            <p className="text-ink/60">No active flood warning or advisory, so flood areas are hidden.</p>
          )}
          {trip.weather.alerts.length > 0 && (
            <ul className="mt-1 space-y-1 text-coral">
              {trip.weather.alerts.map((alert) => (
                <li key={alert}>{alert}</li>
              ))}
            </ul>
          )}
        </div>
      )}
      {trip.routes.map((route) => (
        <RouteCard
          key={route.id}
          route={route}
          recommended={route.id === trip.recommended_id}
          selected={route.id === selectedId}
          onSelect={() => onSelect(route.id)}
        />
      ))}
      <div className="rounded-2xl border border-line bg-white px-3 py-3 text-ink" aria-live="polite">
        {explaining && (
          <>
            <p className="text-xs font-medium tracking-wide text-coral uppercase">Explanation</p>
            <p className="mt-2 animate-pulse text-sm text-ink/70">Writing the explanation…</p>
          </>
        )}
        {!explaining && explanation && (
          <>
            <p className="text-xs font-medium tracking-wide text-coral uppercase">
              {explanation.model.includes("gemma") ? "Gemma 4" : "Route scores"}
            </p>
            <p className="mt-1 text-sm leading-6">{explanation.text}</p>
            <p className="mt-2 text-xs text-ink/50">This note describes the scores above. It does not calculate the route.</p>
          </>
        )}
        {explainGaps.length > 0 && (
          <ul className="mt-2 space-y-1 text-xs text-ink/60">
            {explainGaps.map((gap) => (
              <li key={gap}>{GAP_COPY[gap] || gap}</li>
            ))}
          </ul>
        )}
      </div>
      {trip.data_gaps.length > 0 && (
        <ul className="space-y-1 text-xs text-ink/60">
          {trip.data_gaps.map((gap) => (
            <li key={gap}>{GAP_COPY[gap] || gap}</li>
          ))}
        </ul>
      )}
    </div>
  );
}
