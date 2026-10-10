import type {
  AlertsResponse,
  AssistResponse,
  Explanation,
  Language,
  Place,
  PlanResponse,
  PrepareResponse,
  TripResponse,
} from "./types";

export type TripBody = {
  origin: Place;
  destination: Place;
  depart_at?: string;
};

function messageFrom(payload: unknown, status: number): string {
  if (payload && typeof payload === "object" && "detail" in payload) {
    const detail = (payload as { detail: unknown }).detail;
    if (typeof detail === "string") return detail;
  }
  return `Request failed (${status}).`;
}

async function readError(response: Response): Promise<string> {
  try {
    return messageFrom(await response.json(), response.status);
  } catch {
    return `Request failed (${response.status}).`;
  }
}

export async function planRoute(body: TripBody): Promise<TripResponse> {
  try {
    const response = await fetch("/api/routes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(25_000),
    });
    if (!response.ok) throw new Error(await readError(response));
    return response.json();
  } catch (error) {
    if (error instanceof DOMException && error.name === "TimeoutError") {
      throw new Error("The route check took too long. Try again.");
    }
    throw error;
  }
}

export async function fetchAlerts(lat?: number, lng?: number, language: Language = "en"): Promise<AlertsResponse> {
  const params = new URLSearchParams({ language });
  if (lat != null && lng != null) {
    params.set("lat", String(lat));
    params.set("lng", String(lng));
  }
  const response = await fetch(`/api/alerts?${params}`, { signal: AbortSignal.timeout(20_000) });
  if (!response.ok) throw new Error(await readError(response));
  return response.json();
}

export async function prepareChecklist(body: {
  location?: Place;
  notes?: string;
  people?: number;
  pets?: boolean;
  mobility?: string;
  medical?: string;
  language: Language;
}): Promise<PrepareResponse> {
  return postJson("/api/prepare", body, 55_000);
}

export async function assistNearby(body: {
  location: Place;
  needs: string[];
  language: Language;
}): Promise<AssistResponse> {
  return postJson("/api/assist", body, 40_000);
}

export async function planDay(body: {
  age: number;
  interests: string[];
  budget: string;
  vibe: string;
  start: Place;
  day?: string;
  language: Language;
  needs: string[];
}): Promise<PlanResponse> {
  return postJson("/api/plan", body, 220_000);
}

async function postJson<T>(path: string, body: unknown, timeout: number): Promise<T> {
  try {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeout),
    });
    if (!response.ok) throw new Error(await readError(response));
    return response.json();
  } catch (error) {
    if (error instanceof DOMException && error.name === "TimeoutError") {
      throw new Error("That request took too long. Try again.");
    }
    throw error;
  }
}

export async function explainRoute(
  facts: Record<string, unknown>,
  language: Language = "en",
): Promise<{ explanation: Explanation; data_gaps: string[] }> {
  try {
    const response = await fetch("/api/explain", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ facts, language }),
      signal: AbortSignal.timeout(55_000),
    });
    if (!response.ok) throw new Error(await readError(response));
    return response.json();
  } catch (error) {
    if (error instanceof DOMException && error.name === "TimeoutError") {
      throw new Error("The explanation took too long.");
    }
    throw error;
  }
}

export async function checkHealth(): Promise<boolean> {
  try {
    const response = await fetch("/api/health");
    return response.ok;
  } catch {
    return false;
  }
}
