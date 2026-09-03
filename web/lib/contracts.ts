import { foundry, robinhood, robinhoodTestnet } from "viem/chains";
import type { Chain } from "viem";

import d31337 from "./deployments/31337.json";
import d46630 from "./deployments/46630.json";
import d4663 from "./deployments/4663.json";
import m31337 from "./deployments/31337.mocks.json";
import m46630 from "./deployments/46630.mocks.json";
import m4663 from "./deployments/4663.mocks.json";

export type Address = `0x${string}`;

export type Deployment = {
  stockPack: Address;
  renderer: Address;
  artist: Address;
  chainId: number;
  deployBlock: number;
};

type Network = "local" | "testnet" | "mainnet";

const NETWORK = (process.env.NEXT_PUBLIC_CHAIN ?? "local") as Network;

const CHAINS: Record<Network, Chain> = {
  local: foundry,
  testnet: robinhoodTestnet,
  mainnet: robinhood,
};

const DEPLOYMENTS: Record<Network, Deployment> = {
  local: d31337 as Deployment,
  testnet: d46630 as Deployment,
  mainnet: d4663 as Deployment,
};

const MOCKS: Record<Network, Record<string, string>> = {
  local: m31337 as unknown as Record<string, string>,
  testnet: m46630 as unknown as Record<string, string>,
  mainnet: m4663 as unknown as Record<string, string>,
};

export const network = NETWORK;
export const chain = CHAINS[NETWORK];

export const deployment: Deployment = {
  ...DEPLOYMENTS[NETWORK],
  stockPack: (process.env.NEXT_PUBLIC_STOCKPACK_ADDRESS as Address) ?? DEPLOYMENTS[NETWORK].stockPack,
};

/** Server-side RPC (indexer, og route). The public RPCs are rate-limited — set RPC_URL. */
export const serverRpcUrl =
  process.env.RPC_URL ?? process.env.NEXT_PUBLIC_RPC_URL ?? chain.rpcUrls.default.http[0];

/** Client-side RPC override. */
export const clientRpcUrl = process.env.NEXT_PUBLIC_RPC_URL ?? chain.rpcUrls.default.http[0];

/** Mock stock token addresses recorded by DeployMocks (symbol → address). */
export const mockTokens: { symbol: string; address: Address }[] = Object.entries(MOCKS[NETWORK])
  .filter(([k, v]) => k !== "chainId" && typeof v === "string" && v.startsWith("0x"))
  .map(([symbol, address]) => ({ symbol, address: address as Address }));

export const isDeployed = deployment.stockPack !== "0x0000000000000000000000000000000000000000";

/** OpenSea deep link — only meaningful on mainnet (chain slug "robinhood"). */
export function openSeaAssetUrl(tokenId: bigint | number | string): string | null {
  if (NETWORK !== "mainnet") return null;
  return `https://opensea.io/assets/robinhood/${deployment.stockPack}/${tokenId}`;
}
