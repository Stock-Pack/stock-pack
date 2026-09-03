import { listedTokens } from "@/lib/tokenlist";

/**
 * The price tape at the top of the page — except StockPack has no oracle, so it
 * cannot show prices and does not pretend to. It runs the packable catalogue
 * instead: every ticker the escrow will accept from a verified address on this
 * network, which is the number that actually matters here.
 *
 * Rendered on the server from the static catalogue: no fetch, so it can sit in
 * the root layout without giving every route a network dependency.
 */
export function TickerTape() {
  const tokens = listedTokens();
  if (tokens.length === 0) return null;

  // One pass is measured at `width: max-content`; the keyframe travels exactly
  // -50%, so the second pass lands pixel-for-pixel on the first and the seam
  // never shows. Short catalogues get padded out so a pass always overflows.
  const pass = tokens.length >= 8 ? tokens : [...tokens, ...tokens, ...tokens].slice(0, 24);

  return (
    <div className="tape overflow-hidden border-b border-line bg-bg" aria-hidden>
      <div className="tape-track py-[7px]">
        {[0, 1].map((copy) => (
          <div key={copy} className="flex shrink-0">
            {pass.map((t, i) => (
              <span key={`${copy}-${i}`} className="flex items-center gap-2 px-4 text-[11px] whitespace-nowrap">
                <span className="font-medium text-ink">{t.symbol}</span>
                <span className="text-muted">{t.category === "coin" ? "coin" : "stock"}</span>
              </span>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
