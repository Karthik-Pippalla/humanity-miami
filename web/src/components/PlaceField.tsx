import { useEffect, useRef } from "react";
import { useMapsLibrary } from "@vis.gl/react-google-maps";
import type { Place } from "../types";

type Props = {
  label: string;
  placeholder: string;
  value: Place | null;
  onChange: (place: Place) => void;
};

function parseLatLng(text: string): { lat: number; lng: number } | null {
  const match = text.trim().match(/^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/);
  if (!match) return null;
  const lat = Number(match[1]);
  const lng = Number(match[2]);
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return { lat, lng };
}

export function PlaceField({ label, placeholder, value, onChange }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const places = useMapsLibrary("places");

  useEffect(() => {
    if (inputRef.current && value && document.activeElement !== inputRef.current) {
      inputRef.current.value = value.label;
    }
  }, [value]);

  useEffect(() => {
    if (!places || !inputRef.current) return;
    const autocomplete = new places.Autocomplete(inputRef.current, {
      fields: ["geometry", "formatted_address", "name"],
      componentRestrictions: { country: "us" },
      bounds: new google.maps.LatLngBounds({ lat: 25.4, lng: -80.7 }, { lat: 26.05, lng: -80.0 }),
    });
    const listener = autocomplete.addListener("place_changed", () => {
      const place = autocomplete.getPlace();
      const location = place.geometry?.location;
      if (!location) return;
      onChangeRef.current({
        label: place.formatted_address || place.name || "Selected place",
        lat: location.lat(),
        lng: location.lng(),
      });
    });
    return () => {
      listener.remove();
      google.maps.event.clearInstanceListeners(autocomplete);
    };
  }, [places]);

  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium tracking-wide text-coral uppercase">{label}</span>
      <input
        ref={inputRef}
        defaultValue={value?.label ?? ""}
        placeholder={placeholder}
        onBlur={(event) => {
          const parsed = parseLatLng(event.target.value);
          if (parsed) onChangeRef.current({ label: event.target.value, ...parsed });
        }}
        className="w-full rounded-xl border border-line bg-white px-3 py-2.5 text-sm text-ink outline-none focus:border-coral"
      />
    </label>
  );
}

export function PlainPlaceField({ label, placeholder, value, onChange }: Props) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-medium tracking-wide text-coral uppercase">{label}</span>
      <input
        value={value?.label ?? ""}
        placeholder={placeholder}
        onChange={(event) => {
          const parsed = parseLatLng(event.target.value);
          if (parsed) onChange({ label: event.target.value, ...parsed });
          else onChange({ label: event.target.value, lat: Number.NaN, lng: Number.NaN });
        }}
        className="w-full rounded-xl border border-line bg-white px-3 py-2.5 text-sm text-ink outline-none focus:border-coral"
      />
    </label>
  );
}
