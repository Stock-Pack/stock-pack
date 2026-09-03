import { timingSafeEqual } from "crypto";

import { NextRequest, NextResponse } from "next/server";

import { mongoEnabled } from "@/lib/db";
import { sync } from "@/lib/indexer";

export const dynamic = "force-dynamic";

/** Constant-time check of `Authorization: Bearer <CRON_SECRET>`. Header-only —
 *  query-string secrets end up in access logs, browser history, and Referers. */
function authorized(req: NextRequest, secret: string): boolean {
  const got = Buffer.from(req.headers.get("authorization") ?? "");
  const want = Buffer.from(`Bearer ${secret}`);
  return got.length === want.length && timingSafeEqual(got, want);
}

/**
 * GET /api/sync — incremental event indexer tick, cron-only. Vercel cron sends
 * `Authorization: Bearer $CRON_SECRET` automatically when the env var is set.
 * Fails closed (503) when CRON_SECRET is unconfigured: this endpoint amplifies
 * into chained getLogs scans + Mongo writes and must never be publicly callable.
 * Read paths stay fresh without it — queryBundles() runs the same incremental
 * sync on every Mongo-mode read.
 */
export async function GET(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    return NextResponse.json({ error: "sync disabled: CRON_SECRET not configured" }, { status: 503 });
  }
  if (!authorized(req, secret)) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  if (!mongoEnabled()) {
    return NextResponse.json({ ok: false, reason: "MONGODB_URI not set — running in chain-scan fallback mode" });
  }
  try {
    const result = await sync();
    return NextResponse.json({ ok: true, ...result });
  } catch (e) {
    console.error("[api/sync]", e);
    return NextResponse.json({ ok: false, error: "sync failed" }, { status: 502 });
  }
}
