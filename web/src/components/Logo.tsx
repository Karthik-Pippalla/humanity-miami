import type { CSSProperties } from "react";

type Mark = {
  d?: string;
  cx?: number;
  cy?: number;
  r?: number;
  width: number;
  group: number;
};

/** Stroke order matches web/src/brand/survive-miami.svg so the pen walks the wheel. */
const marks: Mark[] = [
  { group: 0, width: 18, d: "M 312.99 117.35 A 118.00 118.00 0 1 1 109.12 230.36" },
  { group: 0, width: 18, d: "M 104.58 165.47 A 118.00 118.00 0 0 1 267.99 82.20" },
  { group: 1, width: 12, d: "M 133.40 140.00 A 100.00 100.00 0 0 1 296.60 125.72" },
  { group: 1, width: 12, d: "M 159.58 131.65 A 84.00 84.00 0 0 1 273.99 125.65" },
  { group: 2, width: 8, d: "M 220.00 170.00 L 220.00 132.00" },
  { group: 2, width: 8, d: "M 234.14 175.86 L 261.01 148.99" },
  { group: 2, width: 8, d: "M 240.00 190.00 L 278.00 190.00" },
  { group: 2, width: 8, d: "M 234.14 204.14 L 261.01 231.01" },
  { group: 2, width: 8, d: "M 205.86 204.14 L 178.99 231.01" },
  { group: 2, width: 8, d: "M 200.00 190.00 L 162.00 190.00" },
  { group: 2, width: 8, d: "M 205.86 175.86 L 178.99 148.99" },
  { group: 3, width: 8, cx: 220, cy: 190, r: 16 },
  { group: 3, width: 6, cx: 220, cy: 190, r: 6.5 },
  { group: 3, width: 7, cx: 220, cy: 119, r: 9 },
  { group: 3, width: 7, cx: 270.2, cy: 139.8, r: 9 },
  { group: 3, width: 7, cx: 291, cy: 190, r: 9 },
  { group: 3, width: 7, cx: 270.2, cy: 240.2, r: 9 },
  { group: 3, width: 7, cx: 169.8, cy: 240.2, r: 9 },
  { group: 3, width: 7, cx: 149, cy: 190, r: 9 },
  { group: 3, width: 7, cx: 169.8, cy: 139.8, r: 9 },
  { group: 4, width: 9, d: "M 209 206 L 174 286" },
  { group: 4, width: 9, d: "M 231 206 L 266 286" },
  { group: 4, width: 9, d: "M 152 286 L 194 286" },
  { group: 4, width: 9, d: "M 246 286 L 288 286" },
  { group: 5, width: 8, cx: 291.71, cy: 91.3, r: 14 },
  { group: 5, width: 5, cx: 297.29, cy: 120.41, r: 4.5 },
];

function Wheel() {
  return (
    <svg viewBox="78 48 284 280" className="h-full w-full" aria-hidden="true">
      {marks.map((mark, index) => {
        const style = { "--i": mark.group } as CSSProperties;
        const shared = {
          key: index,
          fill: mark.group === 5 ? "#F07850" : "none",
          stroke: "#F07850",
          strokeWidth: mark.width,
          strokeLinecap: "round" as const,
          strokeLinejoin: "round" as const,
          pathLength: 1,
          style,
        };
        if (mark.d) return <path {...shared} d={mark.d} />;
        return <circle {...shared} className={mark.group === 5 ? "logo-dot" : undefined} cx={mark.cx} cy={mark.cy} r={mark.r} />;
      })}
    </svg>
  );
}

function Wordmark({ drawing, large }: { drawing: boolean; large: boolean }) {
  return (
    <div className={drawing ? "logo-wordmark" : undefined}>
      <p className={large ? "font-sans text-4xl leading-none font-extrabold tracking-tight text-white sm:text-5xl" : "font-sans text-[1.65rem] leading-none font-extrabold tracking-tight text-white"}>
        Survive Miami
      </p>
      <p className={large ? "mt-3 text-sm font-medium tracking-[0.18em] text-coral" : "mt-1 text-[0.7rem] font-medium tracking-[0.16em] text-coral"}>
        Live the Miami Life.
      </p>
    </div>
  );
}

export function Logo({ mode = "static", layout = "inline" }: { mode?: "static" | "draw"; layout?: "inline" | "stack" }) {
  const drawing = mode === "draw";
  const wheel = (
    <div className={layout === "stack" ? "h-56 w-56 sm:h-64 sm:w-64" : "h-14 w-14 shrink-0"}>
      <Wheel />
    </div>
  );
  const words = <Wordmark drawing={drawing} large={layout === "stack"} />;
  if (layout === "stack") {
    return (
      <div className={`flex flex-col items-center text-center ${drawing ? "logo-draw" : ""}`}>
        {wheel}
        <div className="mt-2">{words}</div>
      </div>
    );
  }
  return (
    <div className={`flex items-center gap-3 ${drawing ? "logo-draw" : ""}`}>
      {wheel}
      {words}
    </div>
  );
}
