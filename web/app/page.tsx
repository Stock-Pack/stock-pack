import Link from "next/link";

import { BundleCard } from "@/components/BundleCard";
import { Reveal } from "@/components/Reveal";
import { PackFlow } from "@/components/PackFlow";
import { deployment, isDeployed, network } from "@/lib/contracts";
import type { BundleDoc } from "@/lib/db";
import { shortAddress } from "@/lib/display";
import { queryBundles } from "@/lib/indexer";
import { listedTokens } from "@/lib/tokenlist";

export const dynamic = "force-dynamic";

/** Pulled larger than the grid shows so the stat strip can count without a second
 *  query; past this the headline count becomes "60+" rather than a wrong number. */
const SCAN_LIMIT = 60;
const GRID_LIMIT = 8; // two full rows at the widest breakpoint

const CHAIN_LABEL =
  network === "mainnet" ? "Robinhood Chain" : network === "testnet" ? "Robinhood Testnet" : "Local Anvil";

const STEPS = [
  {
    n: "01",
    t: "Pick your positions.",
    d: "Choose any tokenized stocks or coins your wallet holds, in any amounts. No preset weights, no minimums, no curation committee — the basket is whatever you say it is.",
  },
  {
    n: "02",
    t: "Seal it into a card.",
    d: "One transaction moves the exact balances into the escrow and mints you an ERC-721 whose artwork and traits are generated fully on-chain. The composition is frozen at mint.",
  },
  {
    n: "03",
    t: "Trade it, or burn it.",
    d: "The card trades anywhere ERC-721s trade. Whoever holds it can burn it at any moment and withdraw every underlying token in one transaction, at the exact recorded amounts.",
  },
];

const CANNOT = [
  {
    t: "Cannot be paused.",
    d: "There is no owner, no pause flag and no upgrade path. Redemption has no gate anywhere in the contract.",
  },
  {
    t: "Cannot be drained by approvals.",
    d: "Burning is strictly ownerOf-only. A standing marketplace setApprovalForAll can move the card, never destroy the basket.",
  },
  {
    t: "Cannot be mispriced.",
    d: "No oracle is read on any path. A basket redeems for the units it was sealed with, whatever any feed says they are worth.",
  },
  {
    t: "Cannot be under-collateralised.",
    d: "Deposits are checked by balance delta, so fee-on-transfer tokens are rejected at the door and totalEscrowed always matches what is held.",
  },
];

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="py-8 pr-6">
      <p className="eyebrow">{label}</p>
      <p className="display mt-2 text-[clamp(1.4rem,2.4vw,1.9rem)] leading-tight">{value}</p>
      {sub && <p className="mini mt-1">{sub}</p>}
    </div>
  );
}

export default async function Home() {
  let bundles: BundleDoc[] = [];
  let scanFailed = false;
  if (isDeployed) {
    try {
      bundles = await queryBundles({ limit: SCAN_LIMIT });
    } catch (e) {
      // never surface raw errors: RPC/Mongo messages can embed the server URL (incl. keys)
      console.error("[home] bundle scan failed", e);
      scanFailed = true;
    }
  }

  const live = bundles.filter((b) => b.status === "live");
  const sealedCount = bundles.length >= SCAN_LIMIT ? `${SCAN_LIMIT}+` : String(bundles.length);
  const catalogue = listedTokens().length;

  return (
    <>
      {/* ── Hero ─────────────────────────────────────────────────────────── */}
      <section className="border-b border-line">
        <div className="mx-auto grid max-w-[1280px] items-center gap-12 px-6 py-16 lg:grid-cols-[1fr_1fr] lg:gap-16 lg:py-24">
          <div>
            <p className="inline-flex items-center gap-2 border border-line px-3 py-1.5 text-[11px] tracking-[0.18em] uppercase">
              <span aria-hidden className="block h-[7px] w-[7px] bg-accent" />
              RWA · Tokenized Equity · On-Chain Settlement Layer
            </p>

            <h1 className="display h-hero mt-8">
              Tokenized stock
              <br />
              baskets, sealed
              <br />
              {/* the square is punctuation, not decoration — it must never wrap onto
                  a line of its own, so it is glued to the last word */}
              <span className="whitespace-nowrap">
                on-chain
                <span aria-hidden className="ml-2 inline-block h-[0.5em] w-[0.5em] align-baseline bg-accent" />
              </span>
            </h1>

            <p className="mt-6 max-w-lg text-muted">
              Deposit any basket of tokenized stocks — real-world assets, on-chain. StockPack escrows the exact
              balances and mints you one tradable card. Burn it whenever you like and take every token back, in one
              transaction.
            </p>

            <div className="mt-10 flex flex-wrap items-center gap-4">
              <Link href="/create" className="btn btn-primary">
                Pack a basket
              </Link>
              <Link href="#bundles" className="btn btn-ghost">
                Browse bundles
              </Link>
              <span className="text-[12px] text-muted">fee 0.00%</span>
            </div>

            {/* Category strip. Someone scanning for five seconds should be able to place
                this product without reading a sentence. */}
            <ul className="mt-10 flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-line pt-5">
              {["Real-world assets", "On-chain equity layer", "Arbitrum Layer 2", "Composable primitive"].map((t) => (
                <li key={t} className="flex items-center gap-2 text-[11px] tracking-[0.18em] uppercase text-muted">
                  <span aria-hidden className="block h-[5px] w-[5px] bg-accent" />
                  {t}
                </li>
              ))}
            </ul>
          </div>

          {/* min-w-0: a grid item is floored at its content's min-content width, so
              without this the 420px-wide diagram widens the column instead of
              scrolling inside it, and the whole page gains a horizontal scrollbar */}
          <div className="panel min-w-0">
            <div className="panel-head">
              <span>pack_flow — bundle</span>
              <span>1 TX · ~2s</span>
            </div>
            {/* The diagram has a fixed aspect ratio; below ~640px scaling it to the
                panel width would drop the node labels under 8px, so it keeps a legible
                height and scrolls inside its own box instead. */}
            <div className="min-w-0 overflow-x-auto bg-raise px-4 py-5">
              <PackFlow className="h-[190px] w-auto max-w-none sm:h-auto sm:w-full" />
            </div>
            <p className="mini border-t border-line px-4 py-4 text-center">
              Your tokens go in untouched — you get one card back that redeems for exactly them.
            </p>
          </div>
        </div>
      </section>

      {/* ── Positioning ──────────────────────────────────────────────────── */}
      <section className="border-b border-line bg-raise">
        <div className="mx-auto max-w-[1280px] px-6 py-14 sm:py-16">
          <p className="eyebrow">The layer</p>
          <p className="display mt-4 max-w-4xl text-[clamp(1.35rem,2.6vw,2rem)] leading-[1.25]">
            StockPack is the <span className="text-accent-ink">ownership layer</span> for tokenized equity — real-world
            assets wrapped into a single composable primitive, settled on an Arbitrum Layer 2.
          </p>
          <p className="mt-4 max-w-2xl text-muted">
            Stock tokens are the asset layer. StockPack is the layer on top: one ERC-721 that carries a whole
            portfolio, trades anywhere, and unwraps to the exact underlying at any moment. No oracle in the path, no
            fee, no key that can touch what is inside.
          </p>
        </div>
      </section>

      {/* ── Bundles ──────────────────────────────────────────────────────── */}
      <section id="bundles" className="border-b border-line">
        <div className="mx-auto max-w-[1280px] px-6 py-16 sm:py-20">
          <p className="eyebrow">Bundles</p>
          <h2 className="display h-section mt-4">Live bundles. Sealed today.</h2>
          <div className="mt-3 flex flex-wrap items-end justify-between gap-4">
            <p className="max-w-xl text-muted">
              Every bundle here is a real card holding real balances. Composition is fixed at mint and verifiable
              on-chain — no rebalancing, no manager, no discretion.
            </p>
            <Link href="/my" className="link-arrow">
              my bundles &rarr;
            </Link>
          </div>

          <div className="mt-10">
            {!isDeployed ? (
              <p className="panel px-4 py-6 text-muted">
                Contracts are not deployed for the configured network ({network}). Deploy with{" "}
                <span className="text-ink">forge script script/Deploy.s.sol</span> and sync{" "}
                <span className="text-ink">deployments/</span>.
              </p>
            ) : scanFailed ? (
              <p className="panel px-4 py-6 text-[var(--color-danger)]">
                Could not load bundles right now — please try again shortly.
              </p>
            ) : live.length === 0 ? (
              <div className="panel flex flex-col items-start gap-4 px-6 py-10 sm:flex-row sm:items-center sm:justify-between">
                <p className="text-muted">No bundles sealed yet on {CHAIN_LABEL}. Be the first.</p>
                <Link href="/create" className="btn btn-primary btn-sm">
                  Pack the first one
                </Link>
              </div>
            ) : (
              <div className="grid auto-rows-fr gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {live.slice(0, GRID_LIMIT).map((b, i) => (
                  // 45ms apart: enough to read as a cascade, short enough that the
                  // last tile is not still arriving after the eye has moved on
                  <Reveal key={b._id} delay={i * 45}>
                    <BundleCard bundle={b} art />
                  </Reveal>
                ))}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* ── Stat strip ───────────────────────────────────────────────────── */}
      <section className="border-b border-line bg-raise">
        <div className="mx-auto grid max-w-[1280px] px-6 py-4 sm:grid-cols-2 lg:grid-cols-4">
          <Stat label="Backing" value="100%" sub="on-chain, per token" />
          <Stat label="Protocol fee" value="0.00%" sub="pack and unpack" />
          <Stat label="Bundles sealed" value={sealedCount} sub={`${catalogue} packable tickers`} />
          <Stat label="Chain" value={CHAIN_LABEL} sub="Arbitrum Orbit L2" />
        </div>
      </section>

      {/* ── How it works ─────────────────────────────────────────────────── */}
      <section id="how" className="border-b border-line">
        <div className="mx-auto max-w-[1280px] px-6 py-16 sm:py-20">
          <p className="eyebrow">How it works</p>
          <h2 className="display h-section mt-4">How StockPack works.</h2>

          <div className="mt-12 grid gap-px border-t border-line md:grid-cols-3">
            {STEPS.map((s, i) => (
              <Reveal key={s.n} delay={i * 60} className="pt-6 md:pr-8">
                <p className="eyebrow">{s.n}</p>
                <h3 className="mt-3 text-[14px] font-medium">{s.t}</h3>
                <p className="mini mt-2 max-w-sm">{s.d}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ── Fees ─────────────────────────────────────────────────────────── */}
      <section className="border-b border-line bg-raise">
        <div className="mx-auto max-w-[1280px] px-6 py-16 sm:py-20">
          <p className="eyebrow">Where the fees go</p>
          <h2 className="display h-section mt-4">Nowhere. There are none.</h2>
          <p className="mt-3 max-w-2xl text-muted">
            There is no fee variable in the contract, because there is no fee. Nothing is skimmed at pack, nothing is
            withheld at unpack, and no address can turn one on later. You pay chain gas and nothing else.
          </p>

          <div className="mt-10 grid gap-4 lg:grid-cols-[1.5fr_1fr]">
            <div className="panel">
              <div className="panel-head">
                <span>fee_split — every pack &amp; unpack</span>
                <span>0.00% fee</span>
              </div>
              <div className="grid divide-line sm:grid-cols-3 sm:divide-x">
                {[
                  { pct: "0%", t: "Protocol", d: "No treasury address exists in the contract." },
                  { pct: "0%", t: "Team", d: "No mint fee, no redemption fee, no spread." },
                  { pct: "100%", t: "You", d: "Every unit you deposit is a unit you can withdraw." },
                ].map((c) => (
                  <div key={c.t} className="px-5 py-6">
                    <p className={`display text-[1.4rem] ${c.pct === "100%" ? "text-accent-ink" : ""}`}>{c.pct}</p>
                    <p className="mt-1 text-[13px]">{c.t}</p>
                    <p className="mini mt-2">{c.d}</p>
                  </div>
                ))}
              </div>
              <p className="mini border-t border-line px-5 py-4">
                Real example: pack 1 NVDA + 1 AAPL + 1 MSFT, burn the card a year later, receive 1 NVDA + 1 AAPL +
                1 MSFT. The escrow keeps nothing.
              </p>
            </div>

            <div className="panel flex flex-col">
              <div className="panel-head">
                <span>solvency</span>
                <span>live</span>
              </div>
              <div className="px-5 py-6">
                <p className="display text-[1.9rem]">1:1</p>
                <p className="mini mt-2">
                  The escrow publishes its own liability ledger. For every token it holds,
                  <span className="text-ink"> balanceOf(escrow) ≥ totalEscrowed(token)</span> — anyone can check it
                  against the chain without asking us anything.
                </p>
              </div>
              <div className="mt-auto space-y-2 border-t border-line px-5 py-4">
                <Link href="#guarantees" className="link-arrow block w-fit">
                  what the contract cannot do &rarr;
                </Link>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── Guarantees ───────────────────────────────────────────────────── */}
      <section id="guarantees" className="border-b border-line">
        <div className="mx-auto max-w-[1280px] px-6 py-16 sm:py-20">
          <p className="eyebrow">Guarantees</p>
          <h2 className="display h-section mt-4">What the contract cannot do.</h2>
          <p className="mt-3 max-w-2xl text-muted">
            Most protocols tell you what they promise. These are the things StockPack is structurally incapable of,
            which is the only kind of promise worth reading.
          </p>

          <div className="panel mt-10">
            <div className="panel-head">
              <span>StockPack.sol — invariants</span>
              <span>enforced on-chain</span>
            </div>
            <div className="grid divide-line md:grid-cols-2 md:divide-x">
              {CANNOT.map((c, i) => (
                <Reveal
                  key={c.t}
                  delay={i * 55}
                  className={`px-5 py-6 ${i < CANNOT.length - 2 ? "border-b border-line" : ""}`}
                >
                  <h3 className="text-[14px] font-medium">{c.t}</h3>
                  <p className="mini mt-2">{c.d}</p>
                </Reveal>
              ))}
            </div>
          </div>

          {isDeployed && (
            <div id="contracts" className="mt-4 flex flex-wrap items-center gap-x-8 gap-y-2 text-[12px]">
              <span className="eyebrow">Deployed</span>
              <span className="text-muted">
                escrow <span className="text-ink">{shortAddress(deployment.stockPack)}</span>
              </span>
              <span className="text-muted">
                renderer <span className="text-ink">{shortAddress(deployment.renderer)}</span>
              </span>
              <span className="text-muted">
                chain <span className="text-ink">{deployment.chainId}</span>
              </span>
            </div>
          )}
        </div>
      </section>

      {/* ── CTA ──────────────────────────────────────────────────────────── */}
      <section className="mx-auto max-w-[1280px] px-6 py-16 sm:py-20">
        <div className="bg-ink text-on-ink px-6 py-20 text-center sm:py-28">
          <h2 className="display mx-auto max-w-2xl text-[clamp(1.75rem,4vw,2.75rem)] leading-[1.08]">
            The basket you want, in one card.
          </h2>
          <p className="mt-4 text-[13px] text-on-ink/70">No manager, no rebalancing, no fees, no minimums.</p>
          <Link href="/create" className="btn mt-10 bg-bg text-ink hover:bg-raise">
            Pack your first basket
          </Link>
        </div>
      </section>
    </>
  );
}
