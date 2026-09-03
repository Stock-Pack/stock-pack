import { NextRequest, NextResponse } from "next/server";

import { deployment, network } from "@/lib/contracts";

export const dynamic = "force-dynamic";

/**
 * Best-effort in-memory throttle (per warm instance) so the route can't drain
 * OpenSea quota. Hardened against key rotation: the map is bounded (expired
 * entries pruned, hard cap on tracked ids) and a global per-minute budget caps
 * upstream calls regardless of how many distinct tokenIds are requested.
 */
const lastRefresh = new Map<string, number>();
const WINDOW_MS = 5 * 60 * 1000;
const MAX_TRACKED = 512;
const GLOBAL_WINDOW_MS = 60 * 1000;
const GLOBAL_MAX_CALLS = 10;
let globalWindowStart = 0;
let globalCalls = 0;

function underGlobalBudget(now: number): boolean {
  if (now - globalWindowStart >= GLOBAL_WINDOW_MS) {
    globalWindowStart = now;
    globalCalls = 0;
  }
  if (globalCalls >= GLOBAL_MAX_CALLS) return false;
  globalCalls += 1;
  return true;
}

function pruneMap(now: number): void {
  if (lastRefresh.size < MAX_TRACKED) return;
  for (const [k, t] of lastRefresh) {
    if (now - t >= WINDOW_MS) lastRefresh.delete(k);
  }
  // still full after pruning: drop oldest insertions (Map preserves order)
  while (lastRefresh.size >= MAX_TRACKED) {
    const oldest = lastRefresh.keys().next().value;
    if (oldest === undefined) break;
    lastRefresh.delete(oldest);
  }
}

/** POST /api/refresh/[tokenId] — proxies OpenSea's metadata refresh (server-side key only). */
export async function POST(_req: NextRequest, ctx: { params: Promise<{ tokenId: string }> }) {
  const { tokenId } = await ctx.params;
  if (!/^\d{1,10}$/.test(tokenId)) return NextResponse.json({ error: "bad tokenId" }, { status: 400 });
  if (network !== "mainnet") return NextResponse.json({ ok: false, reason: "OpenSea indexes mainnet only" });
  const key = process.env.OPENSEA_API_KEY;
  if (!key) return NextResponse.json({ ok: false, reason: "OPENSEA_API_KEY not configured" }, { status: 501 });

  const now = Date.now();
  const last = lastRefresh.get(tokenId) ?? 0;
  if (now - last < WINDOW_MS) return NextResponse.json({ ok: true, throttled: true });
  if (!underGlobalBudget(now)) return NextResponse.json({ ok: true, throttled: true });
  pruneMap(now);
  lastRefresh.set(tokenId, now);

  const url = `https://api.opensea.io/api/v2/chain/robinhood/contract/${deployment.stockPack}/nfts/${tokenId}/refresh`;
  const res = await fetch(url, { method: "POST", headers: { "x-api-key": key } });
  return NextResponse.json({ ok: res.ok, status: res.status });
}
