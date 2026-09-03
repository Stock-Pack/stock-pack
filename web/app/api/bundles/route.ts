import { NextRequest, NextResponse } from "next/server";

import { queryBundles } from "@/lib/indexer";

export const dynamic = "force-dynamic";

/** GET /api/bundles?owner=0x…&status=live&limit=12 — Mongo-indexed (chain-scan fallback). */
export async function GET(req: NextRequest) {
  const p = req.nextUrl.searchParams;
  const owner = p.get("owner") ?? undefined;
  const status = p.get("status") ?? undefined;
  const id = p.get("id");
  const rawLimit = Number(p.get("limit") ?? 12);
  const limit = Number.isFinite(rawLimit) ? Math.min(Math.max(Math.trunc(rawLimit), 1), 50) : 12;
  if (id !== null) {
    if (!/^\d{1,10}$/.test(id)) return NextResponse.json({ error: "bad id" }, { status: 400 });
    try {
      const rows = await queryBundles({ id: Number(id), limit: 1 });
      return NextResponse.json({ bundle: rows[0] ?? null });
    } catch (e) {
      console.error("[api/bundles]", e);
      return NextResponse.json({ error: "upstream unavailable" }, { status: 502 });
    }
  }
  if (owner && !/^0x[0-9a-fA-F]{40}$/.test(owner)) {
    return NextResponse.json({ error: "bad owner" }, { status: 400 });
  }
  if (status && !["live", "redeemed", "emergency"].includes(status)) {
    return NextResponse.json({ error: "bad status" }, { status: 400 });
  }
  try {
    const bundles = await queryBundles({ owner, status, limit });
    return NextResponse.json({ bundles });
  } catch (e) {
    console.error("[api/bundles]", e);
    return NextResponse.json({ error: "upstream unavailable" }, { status: 502 });
  }
}
