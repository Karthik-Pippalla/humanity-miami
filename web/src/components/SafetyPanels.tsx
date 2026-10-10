import { useState } from "react";
import { assistNearby, fetchAlerts, planDay, prepareChecklist } from "../api";
import { GAP_COPY, type AlertsResponse, type AssistResponse, type Language, type Place, type PlanResponse, type PrepareResponse } from "../types";

const fieldClass = "w-full rounded-xl border border-line bg-white px-3 py-2.5 text-sm text-ink outline-none focus:border-coral";
const labelClass = "mb-1 block text-xs font-medium tracking-wide text-coral uppercase";

export function LanguageControl({ value, onChange }: { value: Language; onChange: (value: Language) => void }) {
  const options: { id: Language; label: string }[] = [
    { id: "en", label: "English" },
    { id: "es", label: "Español" },
    { id: "ht", label: "Kreyòl" },
  ];
  return (
    <div className="flex gap-1 rounded-xl bg-white/10 p-1" role="group" aria-label="Language">
      {options.map((option) => (
        <button
          key={option.id}
          type="button"
          onClick={() => onChange(option.id)}
          className={`flex-1 rounded-lg px-2 py-1.5 text-xs font-semibold ${
            value === option.id ? "bg-coral text-navy" : "text-white/80"
          }`}
          aria-pressed={value === option.id}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function NeedsControl({ value, onChange }: { value: string[]; onChange: (value: string[]) => void }) {
  const options = [
    ["elderly", "Elderly"],
    ["wheelchair", "Wheelchair"],
    ["medical", "Medical"],
    ["no_car", "No car"],
  ] as const;
  return (
    <fieldset>
      <legend className={labelClass}>Needs</legend>
      <div className="flex flex-wrap gap-2">
        {options.map(([id, label]) => {
          const checked = value.includes(id);
          return (
            <label key={id} className={`rounded-full px-3 py-1 text-xs font-medium ${checked ? "bg-coral text-navy" : "bg-white/10 text-white"}`}>
              <input
                type="checkbox"
                className="sr-only"
                checked={checked}
                onChange={() => onChange(checked ? value.filter((item) => item !== id) : [...value, id])}
              />
              {label}
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}

function Gaps({ gaps }: { gaps: string[] }) {
  if (gaps.length === 0) return null;
  return (
    <ul className="space-y-1 text-xs text-white/70">
      {gaps.map((gap) => (
        <li key={gap}>{GAP_COPY[gap] || gap}</li>
      ))}
    </ul>
  );
}

function clock(value: string): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

export function AlertsPanel({ language, here }: { language: Language; here: Place | null }) {
  const [report, setReport] = useState<AlertsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function load(place: Place | null) {
    setLoading(true);
    setError(null);
    try {
      setReport(await fetchAlerts(place?.lat, place?.lng, language));
    } catch (caught) {
      setReport(null);
      setError(caught instanceof Error ? caught.message : "Weather alerts could not be loaded.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-white/80">Official storm, heavy-rain, hurricane, and flood alerts for a location.</p>
      <button type="button" onClick={() => void load(here)} disabled={!here || loading} className="w-full rounded-xl bg-coral px-3 py-2.5 text-sm font-semibold text-navy disabled:opacity-50">
        {loading ? "Loading alerts…" : here ? "Show alerts here" : "Use your location first"}
      </button>
      {error && <p className="rounded-xl bg-white px-3 py-2 text-sm text-coral">{error}</p>}
      {report && (
        <div className="space-y-3 text-sm text-white">
          <p>
            {report.place}
            {report.forecast ? ` · ${report.forecast}` : ""}
            {report.temperature_f != null ? ` · ${Math.round(report.temperature_f)}°F` : ""}
          </p>
          {report.advisories.length === 0 && <p className="text-white/70">No storm, heavy-rain, hurricane, or flood alert is active at this point.</p>}
          {report.advisories.map((item) => (
            <article key={`${item.event}-${item.headline}`} className="rounded-2xl bg-white px-3 py-3 text-ink">
              <p className="text-xs font-semibold tracking-wide text-coral uppercase">
                {item.category.replace("_", " ")}
                {item.is_watch ? " · watch" : ""}
                {item.severity ? ` · ${item.severity}` : ""}
              </p>
              <h3 className="mt-1 text-sm font-semibold">{item.headline}</h3>
              {item.plain_language && <p className="mt-2 text-sm leading-5">{item.plain_language}</p>}
              <p className="mt-2 text-xs text-ink/50">The headline is the official National Weather Service text. The paragraph is an explanation.</p>
            </article>
          ))}
          <Gaps gaps={report.data_gaps} />
          <p className="text-xs leading-5 text-white/60">{report.notice}</p>
        </div>
      )}
    </div>
  );
}

export function PreparePanel({ language, here }: { language: Language; here: Place | null }) {
  const [notes, setNotes] = useState("");
  const [people, setPeople] = useState("2");
  const [pets, setPets] = useState(false);
  const [mobility, setMobility] = useState("");
  const [medical, setMedical] = useState("");
  const [needs, setNeeds] = useState<string[]>([]);
  const [checklist, setChecklist] = useState<PrepareResponse | null>(null);
  const [help, setHelp] = useState<AssistResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<"prepare" | "assist" | null>(null);

  async function prepare() {
    setLoading("prepare");
    setError(null);
    try {
      setChecklist(
        await prepareChecklist({
          location: here ?? undefined,
          notes,
          people: Number(people) || undefined,
          pets,
          mobility,
          medical,
          language,
        }),
      );
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "The checklist could not be created.");
    } finally {
      setLoading(null);
    }
  }

  async function findHelp() {
    if (!here) return;
    setLoading("assist");
    setError(null);
    try {
      setHelp(await assistNearby({ location: here, needs, language }));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Nearby resources could not be loaded.");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-white/80">A Gemma 4 checklist from your notes and the alerts at your location.</p>
      <label className="block">
        <span className={labelClass}>People</span>
        <input className={fieldClass} inputMode="numeric" value={people} onChange={(event) => setPeople(event.target.value)} />
      </label>
      <label className="flex items-center gap-2 text-sm text-white">
        <input type="checkbox" checked={pets} onChange={(event) => setPets(event.target.checked)} />
        Pets at home
      </label>
      <label className="block">
        <span className={labelClass}>Mobility</span>
        <input className={fieldClass} value={mobility} placeholder="Walker, wheelchair, limited stairs" onChange={(event) => setMobility(event.target.value)} />
      </label>
      <label className="block">
        <span className={labelClass}>Medical</span>
        <input className={fieldClass} value={medical} placeholder="Daily medicine, oxygen, dialysis" onChange={(event) => setMedical(event.target.value)} />
      </label>
      <label className="block">
        <span className={labelClass}>Other notes</span>
        <textarea className={fieldClass} rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} />
      </label>
      <button type="button" onClick={() => void prepare()} disabled={loading !== null} className="w-full rounded-xl bg-coral px-3 py-2.5 text-sm font-semibold text-navy disabled:opacity-50">
        {loading === "prepare" ? "Preparing…" : "Build checklist"}
      </button>
      {checklist && (
        <div className="space-y-2">
          {checklist.items.map((item) => (
            <article key={`${item.category}-${item.action}`} className="rounded-2xl bg-white px-3 py-3 text-ink">
              <p className="text-xs font-semibold tracking-wide text-coral uppercase">{item.category}</p>
              <p className="mt-1 text-sm font-semibold">{item.action}</p>
              <p className="mt-1 text-sm leading-5 text-ink/70">{item.why}</p>
            </article>
          ))}
          <p className="text-xs text-white/60">{checklist.model.includes("gemma") ? "Gemma 4" : "Standard checklist"}</p>
          <Gaps gaps={checklist.data_gaps} />
          <p className="text-xs leading-5 text-white/60">{checklist.notice}</p>
        </div>
      )}
      <div className="border-t border-white/10 pt-3">
        <h3 className="text-sm font-semibold text-white">Nearby emergency help</h3>
        <p className="mt-1 text-xs leading-5 text-white/65">Hospitals and Miami-Dade emergency information for elderly residents, wheelchair users, and other needs.</p>
        <div className="mt-3">
          <NeedsControl value={needs} onChange={setNeeds} />
        </div>
        <button type="button" onClick={() => void findHelp()} disabled={!here || loading !== null} className="mt-3 w-full rounded-xl border border-white/30 px-3 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
          {loading === "assist" ? "Looking nearby…" : here ? "Find nearby help" : "Use your location first"}
        </button>
      </div>
      {help && (
        <div className="space-y-2">
          {help.resources.map((item) => (
            <article key={item.id} className="rounded-2xl bg-white px-3 py-3 text-ink">
              <p className="text-sm font-semibold">{item.name}</p>
              <p className="text-xs text-ink/60">{item.address}</p>
              <p className="mt-1 text-xs">
                {item.drive_minutes != null ? `${item.drive_minutes} min` : "Time unavailable"}
                {item.estimated ? " · estimated" : ""}
              </p>
              <p className="mt-1 text-xs leading-5 text-ink/70">{item.confirm}</p>
              <a className="mt-1 inline-block text-xs font-semibold text-coral" href={item.source_url} target="_blank" rel="noreferrer">
                Official page
              </a>
            </article>
          ))}
          {help.steps.map((item) => (
            <p key={item.action} className="text-sm text-white/85">
              <span className="font-semibold">{item.category}. </span>
              {item.action}
            </p>
          ))}
          <Gaps gaps={help.data_gaps} />
          <p className="text-xs leading-5 text-white/60">{help.notice}</p>
        </div>
      )}
      {error && <p className="rounded-xl bg-white px-3 py-2 text-sm text-coral">{error}</p>}
    </div>
  );
}

export function PlanPanel({
  language,
  here,
  onPlan,
}: {
  language: Language;
  here: Place | null;
  onPlan: (plan: PlanResponse | null) => void;
}) {
  const [age, setAge] = useState("30");
  const [interests, setInterests] = useState("art, food");
  const [budget, setBudget] = useState("medium");
  const [vibe, setVibe] = useState("relaxed");
  const [day, setDay] = useState("");
  const [needs, setNeeds] = useState<string[]>([]);
  const [plan, setPlan] = useState<PlanResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit() {
    if (!here) return;
    setLoading(true);
    setError(null);
    try {
      const next = await planDay({
        age: Number(age) || 30,
        interests: interests.split(",").map((item) => item.trim()).filter(Boolean),
        budget,
        vibe,
        start: here,
        day: day || undefined,
        language,
        needs,
      });
      setPlan(next);
      onPlan(next);
    } catch (caught) {
      setPlan(null);
      onPlan(null);
      setError(caught instanceof Error ? caught.message : "Plan Miami could not build a day.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-white/80">Tell Plan Miami who is visiting. Gemma 4 picks catalog stops, then drive times set the clock.</p>
      <label className="block">
        <span className={labelClass}>Age</span>
        <input className={fieldClass} inputMode="numeric" value={age} onChange={(event) => setAge(event.target.value)} />
      </label>
      <label className="block">
        <span className={labelClass}>Interests</span>
        <input className={fieldClass} value={interests} onChange={(event) => setInterests(event.target.value)} />
      </label>
      <label className="block">
        <span className={labelClass}>Budget</span>
        <select className={fieldClass} value={budget} onChange={(event) => setBudget(event.target.value)}>
          <option value="free">Free</option>
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
        </select>
      </label>
      <label className="block">
        <span className={labelClass}>Vibe</span>
        <select className={fieldClass} value={vibe} onChange={(event) => setVibe(event.target.value)}>
          <option value="relaxed">Relaxed</option>
          <option value="lively">Lively</option>
          <option value="family">Family</option>
          <option value="outdoors">Outdoors</option>
          <option value="culture">Culture</option>
        </select>
      </label>
      <label className="block">
        <span className={labelClass}>Day</span>
        <input type="datetime-local" className={fieldClass} value={day} onChange={(event) => setDay(event.target.value)} />
      </label>
      <NeedsControl value={needs} onChange={setNeeds} />
      <button type="button" onClick={() => void submit()} disabled={!here || loading} className="w-full rounded-xl bg-coral px-3 py-2.5 text-sm font-semibold text-navy disabled:opacity-50">
        {loading ? "Planning the day…" : here ? "Plan Miami" : "Use your location first"}
      </button>
      {error && <p className="rounded-xl bg-white px-3 py-2 text-sm text-coral">{error}</p>}
      {plan && (
        <div className="space-y-2">
          <p className="text-sm leading-6 text-white">{plan.note}</p>
          {plan.stops.map((stop, index) => (
            <article key={stop.id} className="rounded-2xl bg-white px-3 py-3 text-ink">
              <p className="text-xs font-semibold text-coral">
                {index + 1} · {clock(stop.arrival)}–{clock(stop.leave)}
                {stop.travel_minutes != null ? ` · ${stop.travel_minutes} min drive` : ""}
              </p>
              <h3 className="text-sm font-semibold">{stop.name}</h3>
              <p className="mt-1 text-sm leading-5 text-ink/70">{stop.why}</p>
            </article>
          ))}
          <p className="text-xs text-white/60">{plan.model.includes("gemma") ? "Gemma 4" : "Miami catalog"}</p>
          <Gaps gaps={plan.data_gaps} />
          <p className="text-xs leading-5 text-white/60">{plan.notice}</p>
        </div>
      )}
    </div>
  );
}
