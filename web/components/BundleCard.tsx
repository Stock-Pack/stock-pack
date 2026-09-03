import Link from "next/link";

import { CardTilt } from "@/components/CardTilt";

import type { BundleDoc } from "@/lib/db";
import { formatAmount, sealedDate } from "@/lib/display";
import { findListed } from "@/lib/tokenlist";

/** Deterministic per-symbol hue so a ticker keeps the same swatch across every card
 *  on the page (and between the composition bar and its legend row). */
function symbolHue(symbol: string): number {
  let h = 0;
  for (let i = 0; i < symbol.length; i++) h = (h * 31 + symbol.charCodeAt(i)) % 360;
  return h;
}

const MAX_LEGEND = 5;

/**
 * Gallery card for one sealed bundle. Deliberately shows composition and nothing
 * that looks like performance: StockPack reads no oracle, so there is no price,
 * no TVL and no sparkline to draw. The bar is share-of-basket by position count —
 * the only weighting the contract itself knows about.
 *
 * `art` adds the token's real on-chain artwork above the data. It is opt-in because
 * it costs an image request per card: worth it on a portfolio the holder is browsing,
 * not on every listing surface.
 */
export function BundleCard({ bundle, art = false }: { bundle: BundleDoc; art?: boolean }) {
  const rows = bundle.tokens.map((t, i) => {
    const listed = findListed(t);
    return {
      symbol: listed?.symbol ?? `${t.slice(0, 6)}…`,
      amount: formatAmount(BigInt(bundle.amounts[i] ?? "0"), listed?.decimals ?? 18),
      verified: Boolean(listed),
      hue: symbolHue(listed?.symbol ?? t.slice(2, 8)),
    };
  });
  const redeemed = bundle.status !== "live";
  const share = 100 / Math.max(rows.length, 1);
  const unverified = rows.filter((r) => !r.verified).length;

  return (
    <Link
      href={`/bundle/${bundle._id}`}
      className={`panel group flex h-full flex-col transition-colors hover:border-ink ${redeemed ? "opacity-60" : ""}`}
    >
      {art && (
        // Square, matching the 1:1 canvas, so the grid never reflows as images land.
        // Burned cards have no tokenURI to serve, hence the live-only guard.
        // Full-bleed to the card edges. The tile itself is kept small by the four-up
        // grid, so the artwork gets the whole width rather than being inset — and it
        // is never cropped, since the card is square and so is this box.
        <div className="aspect-square w-full overflow-hidden border-b border-line-soft bg-raise">
          {!redeemed && (
            <CardTilt>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`/api/card/${bundle._id}`}
                alt={`${bundle.name || `Bundle #${bundle._id}`} card artwork`}
                loading="lazy"
                className="block h-full w-full"
              />
            </CardTilt>
          )}
        </div>
      )}

      <div className="flex items-start justify-between gap-3 px-4 pt-4">
        <span className="eyebrow">#{bundle._id}</span>
        <span className="eyebrow">Positions</span>
      </div>

      <div className="flex items-baseline justify-between gap-3 px-4">
        <h3 className="display h-card min-w-0 truncate">{bundle.name || `Bundle #${bundle._id}`}</h3>
        <span className="display h-card shrink-0">{rows.length}</span>
      </div>

      {/* One line, not two: in a four-up grid the longer caption wrapped, and the
          "composition frozen at mint" half already appears in the section header. */}
      <p className="mini px-4 pt-1.5">
        {redeemed ? "Redeemed" : "Sealed"} {sealedDate(bundle.sealedAt)}
      </p>

      {/* Composition bar — one segment per position, hairline-separated. */}
      <div className="mt-4 flex h-[6px] px-4">
        {rows.map((r, i) => (
          <span
            key={i}
            style={{ width: `${share}%`, background: `hsl(${r.hue} 62% 48%)` }}
            className="block border-r border-card last:border-r-0"
          />
        ))}
      </div>

      <ul className="mt-3 grid grid-cols-2 gap-x-4 gap-y-1 px-4">
        {rows.slice(0, MAX_LEGEND).map((r, i) => (
          <li key={i} className="flex items-center gap-1.5 text-[11px] whitespace-nowrap">
            <span
              aria-hidden
              className="block h-[7px] w-[7px] shrink-0"
              style={{ background: `hsl(${r.hue} 62% 48%)` }}
            />
            <span className="truncate text-ink">{r.symbol}</span>
            <span className="ml-auto shrink-0 text-muted">{r.amount}</span>
          </li>
        ))}
        {rows.length > MAX_LEGEND && (
          <li className="text-[11px] text-muted">+{rows.length - MAX_LEGEND} more</li>
        )}
      </ul>

      <div className="mt-auto flex items-end justify-between gap-3 border-t border-line-soft px-4 py-3">
        <div>
          <div className="eyebrow">Backing</div>
          <div className="text-[13px]">{unverified > 0 ? `${unverified} unverified` : "100% on-chain"}</div>
        </div>
        <span className="text-[12px] text-muted transition-colors group-hover:text-ink">view bundle &rarr;</span>
      </div>
    </Link>
  );
}
