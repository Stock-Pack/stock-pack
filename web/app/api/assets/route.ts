import { NextResponse } from "next/server";
import { isAddress } from "viem";

import { registryEnabled } from "@/lib/tokenlist";

/**
 * GET /api/assets — the official Robinhood Stock Token registry for mainnet (chain 4663),
 * proxied because api.robinhood.com sends no CORS headers. Source:
 * https://docs.robinhood.com/chain/stock-token-apis (`GET /rhj/assets`, 15 s upstream cache).
 *
 * This is the same on-chain asset registry the docs table is generated from, so it is the
 * authoritative answer to "is this NVDA the real NVDA". Only served when the real-stock legal
 * gate is on; otherwise an empty list so the client never even learns the addresses.
 */
export const dynamic = "force-dynamic";

const UPSTREAM = "https://api.robinhood.com/rhj/assets";
const CHAIN_ID = 4663;

export type RegistryToken = {
  symbol: string;
  name: string;
  address: `0x${string}`;
  decimals: number;
  logoUrl?: string;
};

type UpstreamAsset = {
  tokenSymbol?: string;
  tokenName?: string;
  tokenDecimals?: number;
  status?: string;
  logoUrl?: string;
  deployments?: { contractAddress?: string; chainId?: number }[];
};

export async function GET() {
  if (!registryEnabled) return NextResponse.json({ tokens: [] as RegistryToken[] });
  try {
    const res = await fetch(UPSTREAM, { next: { revalidate: 300 } });
    if (!res.ok) throw new Error(`upstream ${res.status}`);
    const body = (await res.json()) as { assets?: UpstreamAsset[] };
    const tokens: RegistryToken[] = [];
    for (const a of body.assets ?? []) {
      if (a.status !== "ASSET_STATUS_ACTIVE") continue;
      const dep = a.deployments?.find((d) => d.chainId === CHAIN_ID);
      if (!dep?.contractAddress || !isAddress(dep.contractAddress) || !a.tokenSymbol) continue;
      tokens.push({
        symbol: a.tokenSymbol.slice(0, 11),
        name: (a.tokenName ?? a.tokenSymbol).replace(/\s*•\s*Robinhood Token$/, "").slice(0, 40),
        address: dep.contractAddress,
        decimals: Number.isInteger(a.tokenDecimals) ? (a.tokenDecimals as number) : 18,
        logoUrl: a.logoUrl?.startsWith("https://cdn.robinhood.com/") ? a.logoUrl : undefined,
      });
    }
    return NextResponse.json(
      { tokens },
      { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600" } },
    );
  } catch (e) {
    console.error("[api/assets]", e);
    return NextResponse.json({ error: "upstream unavailable", tokens: [] }, { status: 502 });
  }
}
