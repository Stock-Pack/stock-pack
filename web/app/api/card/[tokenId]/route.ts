import { NextRequest } from "next/server";

import { stockPackAbi } from "@/lib/abi/stockPack";
import { deployment } from "@/lib/contracts";
import { publicClient } from "@/lib/indexer";

export const dynamic = "force-dynamic";

/**
 * GET /api/card/[tokenId] — the card's real on-chain artwork as a standalone SVG.
 *
 * The detail page can afford to read tokenURI in the browser and inline the data URI,
 * but a portfolio grid would make one RPC round trip per card on every render. This
 * resolves it once on the server and lets the CDN hold it, so a grid of twelve costs
 * the visitor twelve cache hits.
 *
 * Cached but revalidated rather than immutable: a basket is frozen at mint, but the
 * escrow's artist can still repoint the renderer, and a stale-forever card would then
 * never pick up new art.
 */
export async function GET(_req: NextRequest, ctx: { params: Promise<{ tokenId: string }> }) {
  const { tokenId } = await ctx.params;
  if (!/^\d{1,10}$/.test(tokenId)) return new Response("bad tokenId", { status: 400 });

  let uri: string;
  try {
    uri = await publicClient().readContract({
      address: deployment.stockPack,
      abi: stockPackAbi,
      functionName: "tokenURI",
      args: [BigInt(tokenId)],
    });
  } catch {
    // burned or never minted — tokenURI reverts
    return new Response("not found", { status: 404 });
  }

  const svg = extractSvg(uri);
  if (!svg) {
    console.error("[api/card] unexpected tokenURI shape for", tokenId);
    return new Response("unavailable", { status: 502 });
  }

  return new Response(svg, {
    headers: {
      "Content-Type": "image/svg+xml; charset=utf-8",
      "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
      // The document is rendered through <img>, which already blocks scripting, but
      // this route is directly reachable — lock it down for anyone who opens it raw.
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; sandbox",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

/** `data:application/json;base64,<json>` → the `image` field's decoded SVG. */
function extractSvg(uri: string): string | null {
  const jsonPart = uri.split(",")[1];
  if (!jsonPart) return null;
  try {
    const json = JSON.parse(Buffer.from(jsonPart, "base64").toString("utf8")) as { image?: unknown };
    const image = json.image;
    if (typeof image !== "string" || !image.startsWith("data:image/svg+xml;base64,")) return null;
    const svg = Buffer.from(image.split(",")[1], "base64").toString("utf8");
    return svg.startsWith("<svg") ? svg : null;
  } catch {
    return null;
  }
}
