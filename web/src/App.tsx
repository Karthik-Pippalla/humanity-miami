import { useEffect, useRef, useState } from "react";
import { APIProvider } from "@vis.gl/react-google-maps";
import { checkHealth, explainRoute, planRoute } from "./api";
import { MapView } from "./components/MapView";
import { PlaceField, PlainPlaceField } from "./components/PlaceField";
import { Logo } from "./components/Logo";
import { Results } from "./components/Results";
import { AlertsPanel, LanguageControl, PlanPanel, PreparePanel } from "./components/SafetyPanels";
import { DEMO, type Explanation, type Language, type Place, type PlanResponse, type TripResponse } from "./types";

type Mode = "drive" | "alerts" | "prepare" | "plan";

const mapsKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY || "";

function isPlace(place: Place | null): place is Place {
  return !!place && Number.isFinite(place.lat) && Number.isFinite(place.lng);
}

export function App() {
  const [origin, setOrigin] = useState<Place | null>(null);
  const [destination, setDestination] = useState<Place | null>(null);
  const [depart, setDepart] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [trip, setTrip] = useState<TripResponse | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [explaining, setExplaining] = useState(false);
  const [explanation, setExplanation] = useState<Explanation | null>(null);
  const [explainGaps, setExplainGaps] = useState<string[]>([]);
  const [apiUp, setApiUp] = useState(true);
  const [mode, setMode] = useState<Mode>("drive");
  const [language, setLanguage] = useState<Language>("en");
  const [here, setHere] = useState<Place | null>(null);
  const [plan, setPlan] = useState<PlanResponse | null>(null);
  const requestId = useRef(0);

  useEffect(() => {
    void checkHealth().then(setApiUp);
  }, []);

  async function submit(nextOrigin: Place | null = origin, nextDestination: Place | null = destination) {
    if (!isPlace(nextOrigin) || !isPlace(nextDestination)) {
      setError("Choose an origin and a destination in South Florida.");
      return;
    }
    const id = ++requestId.current;
    setLoading(true);
    setError(null);
    setExplaining(false);
    setExplanation(null);
    setExplainGaps([]);
    try {
      const result = await planRoute({
        origin: nextOrigin,
        destination: nextDestination,
        depart_at: depart ? depart : undefined,
      });
      if (requestId.current !== id) return;
      setTrip(result);
      setSelectedId(result.recommended_id);
      setLoading(false);
      setExplaining(true);
      try {
        const note = await explainRoute(result.explanation_facts, language);
        if (requestId.current !== id) return;
        setExplanation(note.explanation);
        setExplainGaps(note.data_gaps);
      } catch {
        if (requestId.current !== id) return;
        setExplainGaps(["gemini_unavailable"]);
      } finally {
        if (requestId.current === id) setExplaining(false);
      }
    } catch (caught) {
      if (requestId.current !== id) return;
      setTrip(null);
      setError(caught instanceof Error ? caught.message : "Could not plan a route.");
    } finally {
      if (requestId.current === id) setLoading(false);
    }
  }

  function loadDemo() {
    setOrigin(DEMO.origin);
    setDestination(DEMO.destination);
    void submit(DEMO.origin, DEMO.destination);
  }

  function locate() {
    if (!navigator.geolocation) {
      setError("This browser cannot share a location.");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setHere({ label: "Current location", lat: position.coords.latitude, lng: position.coords.longitude });
        setError(null);
      },
      () => setError("Location permission is needed for alerts, preparation, and Plan Miami."),
    );
  }

  function chooseLanguage(next: Language) {
    setLanguage(next);
    if (!trip) return;
    const id = ++requestId.current;
    setExplaining(true);
    setExplainGaps([]);
    void explainRoute(trip.explanation_facts, next)
      .then((note) => {
        if (requestId.current !== id) return;
        setExplanation(note.explanation);
        setExplainGaps(note.data_gaps);
      })
      .catch(() => {
        if (requestId.current !== id) return;
        setExplainGaps(["gemini_unavailable"]);
      })
      .finally(() => {
        if (requestId.current === id) setExplaining(false);
      });
  }

  const Field = mapsKey ? PlaceField : PlainPlaceField;
  const ready = isPlace(origin) && isPlace(destination);

  const workspace = (
    <div className="grid h-dvh grid-rows-[auto_minmax(0,1fr)]">
      <header className="flex items-center justify-between border-b border-white/10 bg-navy px-4 py-3">
        <div>
          <Logo />
          <p className="mt-1 text-xs text-white/65">Flood-aware driving, alerts, and Plan Miami</p>
        </div>
        <div className="flex items-center gap-3">
          <LanguageControl value={language} onChange={chooseLanguage} />
          {!apiUp && <p className="text-xs text-coral">API is not running on port 8000.</p>}
        </div>
      </header>
      <div className="grid min-h-0 grid-cols-1 md:grid-cols-[minmax(320px,400px)_minmax(0,1fr)]">
        <section className="order-2 min-h-0 overflow-y-auto border-white/10 bg-navy px-4 py-4 md:order-1 md:border-r">
          <div className="mb-3 grid grid-cols-4 gap-1 rounded-xl bg-white/10 p-1" role="tablist">
            {(
              [
                ["drive", "Drive"],
                ["alerts", "Alerts"],
                ["prepare", "Prepare"],
                ["plan", "Plan"],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={mode === id}
                onClick={() => setMode(id)}
                className={`rounded-lg px-2 py-1.5 text-xs font-semibold ${mode === id ? "bg-white text-navy" : "text-white/75"}`}
              >
                {label}
              </button>
            ))}
          </div>
          {mode !== "drive" && (
            <div className="mb-3 flex gap-3">
              <button type="button" onClick={locate} className="text-xs font-semibold text-coral">
                {here ? `Using ${here.lat.toFixed(3)}, ${here.lng.toFixed(3)}` : "Use my location"}
              </button>
              <button
                type="button"
                onClick={() => setHere({ label: "Downtown Miami", lat: 25.7617, lng: -80.1918 })}
                className="text-xs font-semibold text-white/70"
              >
                Downtown Miami
              </button>
            </div>
          )}
          {mode === "alerts" && <AlertsPanel language={language} here={here} />}
          {mode === "prepare" && <PreparePanel language={language} here={here} />}
          {mode === "plan" && <PlanPanel language={language} here={here} onPlan={setPlan} />}
          {mode === "drive" && (
          <>
          <form
            className="space-y-3"
            onSubmit={(event) => {
              event.preventDefault();
              void submit();
            }}
          >
            <Field label="From" placeholder="Little Havana, or 25.76, -80.22" value={origin} onChange={setOrigin} />
            <Field label="To" placeholder="Miami Beach, or 25.79, -80.13" value={destination} onChange={setDestination} />
            <label className="block">
              <span className="mb-1 block text-xs font-medium tracking-wide text-coral uppercase">Depart</span>
              <input
                type="datetime-local"
                value={depart}
                onChange={(event) => setDepart(event.target.value)}
                className="w-full rounded-xl border border-line bg-white px-3 py-2.5 text-sm text-ink outline-none focus:border-coral"
              />
            </label>
            <div className="flex gap-2">
              <button
                type="submit"
                disabled={!ready || loading}
                className="flex-1 rounded-xl bg-coral px-3 py-2.5 text-sm font-semibold text-navy disabled:opacity-50"
              >
                {loading ? "Checking routes…" : "Compare routes"}
              </button>
              <button
                type="button"
                onClick={loadDemo}
                disabled={loading}
                className="rounded-xl border border-white/30 px-3 py-2.5 text-sm font-medium text-white"
              >
                Demo
              </button>
            </div>
          </form>
          <p className="mt-3 text-xs leading-5 text-white/65">
            Travel time is a typical drive, not live traffic. Blue flood areas appear only when a flood warning or
            advisory is active. They are estimated exposure, not a reported road closure. Departure time is used for
            events only.
          </p>
          {trip && (
            <div className="mt-4">
              <Results
                trip={trip}
                selectedId={selectedId}
                onSelect={setSelectedId}
                explaining={explaining}
                explanation={explanation}
                explainGaps={explainGaps}
              />
            </div>
          )}
          </>
          )}
          {error && <p className="mt-3 rounded-xl bg-white px-3 py-2 text-sm text-coral">{error}</p>}
        </section>
        <section className="order-1 min-h-[42dvh] md:order-2 md:min-h-0">
          <MapView trip={mode === "drive" ? trip : null} plan={mode === "plan" ? plan : null} selectedId={selectedId} apiKey={mapsKey} />
        </section>
      </div>
      {loading && (
        <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-navy px-6" role="status" aria-live="polite">
          <Logo mode="draw" layout="stack" />
          <p className="mt-6 text-sm tracking-wide text-white/75">Checking routes…</p>
        </div>
      )}
    </div>
  );

  if (!mapsKey) return workspace;
  return <APIProvider apiKey={mapsKey}>{workspace}</APIProvider>;
}
