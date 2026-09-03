import { ImageResponse } from "next/og";
import { NextRequest } from "next/server";

import { stockPackAbi } from "@/lib/abi/stockPack";
import { deployment } from "@/lib/contracts";
import { accentHue, formatAmount, sealedDate } from "@/lib/display";
import { publicClient } from "@/lib/indexer";
import { findListed } from "@/lib/tokenlist";

export const dynamic = "force-dynamic";

/**
 * GET /api/og/[tokenId] — 1200×630 PNG unfurl card (X/Farcaster won't unfurl SVG).
 * Validates the id on-chain; 404s for burned/unminted ids; immutable-cached (the
 * basket cannot change while the id is live).
 */
export async function GET(_req: NextRequest, ctx: { params: Promise<{ tokenId: string }> }) {
  const { tokenId } = await ctx.params;
  if (!/^\d{1,10}$/.test(tokenId)) return new Response("bad tokenId", { status: 400 });
  const id = BigInt(tokenId);

  const client = publicClient();
  let basket: readonly [readonly `0x${string}`[], readonly bigint[]];
  let meta: readonly [string, `0x${string}`, bigint];
  try {
    [basket, meta] = await Promise.all([
      client.readContract({ address: deployment.stockPack, abi: stockPackAbi, functionName: "getBasket", args: [id] }),
      client.readContract({ address: deployment.stockPack, abi: stockPackAbi, functionName: "bundleMeta", args: [id] }),
    ]);
  } catch {
    return new Response("not found", { status: 404 });
  }

  const [tokens, amounts] = basket;
  const [name, creator, sealedAt] = meta;
  const hue = accentHue(name, creator);

  const rows = await Promise.all(
    tokens.slice(0, 6).map(async (t, i) => {
      const listed = findListed(t);
      let symbol = listed?.symbol;
      if (!symbol) {
        try {
          symbol = (await client.readContract({
            address: t,
            abi: [{ type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] }],
            functionName: "symbol",
          })) as string;
        } catch {
          symbol = `${t.slice(0, 8)}`;
        }
      }
      return { symbol: symbol.slice(0, 11), amount: formatAmount(amounts[i], listed?.decimals ?? 18) };
    }),
  );

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          background: `linear-gradient(135deg, hsl(${hue},45%,14%), hsl(${hue},60%,7%))`,
          padding: 48,
          fontFamily: "sans-serif",
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            flex: 1,
            border: `3px solid hsl(${hue},70%,55%)`,
            borderRadius: 24,
            padding: 48,
          }}
        >
          <div style={{ display: "flex", color: `hsl(${hue},70%,70%)`, fontSize: 24, letterSpacing: 6 }}>
            STOCKPACK BUNDLE
          </div>
          <div style={{ display: "flex", color: "#f5f2ea", fontSize: 64, fontWeight: 700, marginTop: 8 }}>{name}</div>
          <div style={{ display: "flex", flexDirection: "column", marginTop: 32, flex: 1 }}>
            {rows.map((r) => (
              <div
                key={r.symbol}
                style={{ display: "flex", justifyContent: "space-between", color: "#f5f2ea", fontSize: 36, marginTop: 10 }}
              >
                <span style={{ fontWeight: 600 }}>{r.symbol}</span>
                <span style={{ color: "#cfc9bc" }}>{r.amount}</span>
              </div>
            ))}
            {tokens.length > 6 ? (
              <div style={{ display: "flex", color: "#8f897d", fontSize: 28, marginTop: 12 }}>+{tokens.length - 6} more</div>
            ) : null}
          </div>
          <div style={{ display: "flex", color: `hsl(${hue},30%,72%)`, fontSize: 22, letterSpacing: 2 }}>
            StockPack #{tokenId} · SEALED {sealedDate(Number(sealedAt))} · 100% REDEEMABLE
          </div>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
      headers: { "Cache-Control": "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800" },
    },
  );
}
