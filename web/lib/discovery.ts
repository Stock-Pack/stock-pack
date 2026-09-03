import { isAddress } from "viem";

import { chain, network, type Address } from "./contracts";
import { registryEnabled, type ListedToken } from "./tokenlist";

/**
 * Where the create page learns about tokens beyond the curated list:
 *
 *   1. Robinhood's registry (mainnet, legal-gated) → every real Stock Token, verified.
 *   2. The block explorer's per-address token list → whatever the wallet actually holds,
 *      including things we have never heard of. Those come back UNVERIFIED ("other").
 *
 * Both are best-effort: a failure just means the picker falls back to the curated list.
 * The escrow itself never depends on any of this.
 */

export async function fetchRegistryTokens(): Promise<ListedToken[]> {
  if (!registryEnabled) return [];
  const res = await fetch("/api/assets");
  if (!res.ok) return [];
  const body = (await res.json()) as {
    tokens: { symbol: string; name: string; address: Address; decimals: number; logoUrl?: string }[];
  };
  return body.tokens.map((t) => ({
    symbol: t.symbol,
    name: t.name,
    address: t.address,
    decimals: t.decimals,
    verified: true,
    real: true,
    category: "stock" as const,
    hasFaucet: false,
    logoUrl: t.logoUrl,
  }));
}

/** Blockscout v2 `/addresses/{addr}/tokens?type=ERC-20` item (field names vary by version). */
type ExplorerHolding = {
  value?: string;
  token?: { address_hash?: string; address?: string; symbol?: string | null; name?: string | null; decimals?: string | null };
};

/**
 * Tokens the wallet holds according to the explorer. Testnet Blockscout answers with
 * `access-control-allow-origin: *`; mainnet Blockscout sits behind a Cloudflare challenge
 * for cross-origin fetches, so there this usually fails and the registry path carries it.
 */
export async function fetchWalletTokens(address: Address): Promise<ListedToken[]> {
  if (network === "local") return [];
  const base = chain.blockExplorers?.default.url;
  if (!base) return [];
  const out: ListedToken[] = [];
  let url: string | null = `${base}/api/v2/addresses/${address}/tokens?type=ERC-20`;
  for (let page = 0; url && page < 5; page++) {
    const res = await fetch(url, { headers: { accept: "application/json" } });
    if (!res.ok) break;
    const body = (await res.json()) as { items?: ExplorerHolding[]; next_page_params?: Record<string, string> | null };
    for (const h of body.items ?? []) {
      const addr = h.token?.address_hash ?? h.token?.address;
      const decimals = Number(h.token?.decimals);
      if (!addr || !isAddress(addr) || !Number.isInteger(decimals) || decimals < 0 || decimals > 36) continue;
      if (!h.value || BigInt(h.value) === 0n) continue;
      out.push({
        symbol: (h.token?.symbol ?? "???").slice(0, 11),
        name: h.token?.name?.slice(0, 40) ?? undefined,
        address: addr,
        decimals,
        verified: false,
        real: false,
        category: "other",
        hasFaucet: false,
      });
    }
    url = body.next_page_params
      ? `${base}/api/v2/addresses/${address}/tokens?type=ERC-20&${new URLSearchParams(body.next_page_params)}`
      : null;
  }
  return out;
}

/** First occurrence wins — callers pass sources in trust order (curated → registry → wallet). */
export function mergeTokens(...sources: ListedToken[][]): ListedToken[] {
  const seen = new Set<string>();
  const out: ListedToken[] = [];
  for (const src of sources)
    for (const t of src) {
      const k = t.address.toLowerCase();
      if (seen.has(k)) continue;
      seen.add(k);
      out.push(t);
    }
  return out;
}
