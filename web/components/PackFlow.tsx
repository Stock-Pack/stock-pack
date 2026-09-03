/**
 * Hero diagram: three tokenized stocks converge into the escrow and leave as one
 * card. It is drawn rather than photographed because the whole product is this
 * one arrow — many balances in, a single redeemable NFT out.
 *
 * Units are viewBox units, not pixels. The panel renders the SVG about 550px wide,
 * so everything here is scaled by ~0.655 on screen — the radii and font sizes below
 * are chosen so the drawn result lands at ~29px node radius and ~12px labels, which
 * is the optical weight of the 13px mono running alongside it.
 */
const SCALE_NOTE = 840; // viewBox width; height is 380

const INPUTS = [
  { label: "NVDA", y: 72 },
  { label: "AAPL", y: 190 },
  { label: "MSFT", y: 308 },
];

const NODE = { cx: 120, r: 44 };
const ESCROW = { x: 336, y: 144, w: 184, h: 92 };
const CARD = { cx: 706, cy: 190, r: 52 };

const LABEL = { fontSize: 19, fontFamily: "var(--font-mono)" } as const;

export function PackFlow({ className = "" }: { className?: string }) {
  const inDot = (NODE.cx + NODE.r + ESCROW.x) / 2;

  // One source of truth per wire: the same `d` draws the strand and drives the dot
  // travelling along it, so the two can never drift apart.
  const strands = INPUTS.map((n) => ({
    label: n.label,
    d: `M ${NODE.cx + NODE.r} ${n.y} C ${inDot} ${n.y}, ${inDot} 190, ${ESCROW.x} 190`,
  }));
  const exit = `M ${ESCROW.x + ESCROW.w} 190 H ${CARD.cx - CARD.r}`;

  return (
    <svg
      viewBox={`0 0 ${SCALE_NOTE} 380`}
      className={className}
      role="img"
      aria-label="Three tokenized stocks flow into the StockPack escrow and out as a single card NFT"
    >
      <g fill="none" stroke="var(--color-line)" strokeWidth="1.75">
        {strands.map((s) => (
          // cubic with both control points on the midline: the curve leaves the token
          // horizontally and arrives at the escrow horizontally, so the three strands
          // stay parallel where they meet the box
          <path key={s.label} d={s.d} />
        ))}
        <path d={exit} />
      </g>

      {/* The deposits, in flight. Staggered so the three arrive in sequence rather
          than landing as one clump, and the outbound card leaves on the offbeat —
          the diagram then reads left to right the way the transaction does. */}
      <g fill="var(--color-accent)">
        {strands.map((s, i) => (
          <circle
            key={s.label}
            r="5"
            className="flow-dot"
            style={{ offsetPath: `path("${s.d}")`, animationDelay: `${i * 320}ms` }}
          />
        ))}
        <circle r="5" className="flow-dot" style={{ offsetPath: `path("${exit}")`, animationDelay: "1300ms" }} />
      </g>

      {INPUTS.map((n) => (
        <g key={n.label}>
          <circle
            cx={NODE.cx}
            cy={n.y}
            r={NODE.r}
            fill="var(--color-card)"
            stroke="var(--color-ink)"
            strokeWidth="1.75"
          />
          <text
            x={NODE.cx}
            y={n.y}
            textAnchor="middle"
            dominantBaseline="central"
            fill="var(--color-ink)"
            {...LABEL}
          >
            {n.label}
          </text>
        </g>
      ))}

      <rect x={ESCROW.x} y={ESCROW.y} width={ESCROW.w} height={ESCROW.h} fill="var(--color-ink)" />
      <text
        x={ESCROW.x + ESCROW.w / 2}
        y={ESCROW.y + ESCROW.h / 2}
        textAnchor="middle"
        dominantBaseline="central"
        fill="var(--color-on-ink)"
        letterSpacing="1.5"
        {...LABEL}
      >
        ESCROW
      </text>

      <circle cx={CARD.cx} cy={CARD.cy} r={CARD.r} fill="var(--color-ink)" />
      <text x={CARD.cx} y={CARD.cy} textAnchor="middle" dominantBaseline="central" fill="var(--color-on-ink)" {...LABEL}>
        CARD
      </text>
    </svg>
  );
}
