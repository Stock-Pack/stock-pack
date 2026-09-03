import type { PublicClient } from "viem";

import { network, type Address } from "./contracts";

/**
 * Uniswap V3 on Robinhood Chain mainnet (chain 4663) — the primary public AMM for
 * Stock Tokens. Addresses from the official Uniswap deployments registry
 * (github.com/Uniswap/contracts/blob/main/deployments/4663.md), verified on-chain
 * 2026-09-02 (both have code; NVDA/USDG pools quote at the 500 and 3000 fee tiers).
 *
 * Only exact-OUTPUT single-hop swaps are used: the user says "I want N tokens" and
 * pays at most `amountInMaximum` of the pay token. No testnet deployment is known,
 * so on local/testnet the BuyPanel mints mock tokens instead.
 */
export const UNISWAP: Record<string, { quoterV2: Address; swapRouter02: Address } | undefined> = {
  mainnet: {
    quoterV2: "0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7",
    swapRouter02: "0xcaf681a66d020601342297493863e78c959e5cb2",
  },
};

export const uniswap = UNISWAP[network];
export const swapEnabled = Boolean(uniswap);

/** Fee tiers to probe, cheapest-liquid first. 1bp pools are rare for stocks. */
export const FEE_TIERS = [500, 3000, 10000, 100] as const;

/** Max slippage on the pay side: amountInMaximum = quote * (1 + SLIPPAGE_BPS/10_000). */
export const SLIPPAGE_BPS = 50n;

export const quoterV2Abi = [
  {
    type: "function",
    name: "quoteExactOutputSingle",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "fee", type: "uint24" },
          { name: "sqrtPriceLimitX96", type: "uint160" },
        ],
      },
    ],
    outputs: [
      { name: "amountIn", type: "uint256" },
      { name: "sqrtPriceX96After", type: "uint160" },
      { name: "initializedTicksCrossed", type: "uint32" },
      { name: "gasEstimate", type: "uint256" },
    ],
  },
] as const;

/** SwapRouter02: no `deadline` in the params struct (unlike the v1 SwapRouter). */
export const swapRouter02Abi = [
  {
    type: "function",
    name: "exactOutputSingle",
    stateMutability: "payable",
    inputs: [
      {
        name: "params",
        type: "tuple",
        components: [
          { name: "tokenIn", type: "address" },
          { name: "tokenOut", type: "address" },
          { name: "fee", type: "uint24" },
          { name: "recipient", type: "address" },
          { name: "amountOut", type: "uint256" },
          { name: "amountInMaximum", type: "uint256" },
          { name: "sqrtPriceLimitX96", type: "uint160" },
        ],
      },
    ],
    outputs: [{ name: "amountIn", type: "uint256" }],
  },
] as const;

export type Quote = { fee: number; amountIn: bigint; amountInMax: bigint };

/**
 * Best exact-output quote across fee tiers (lowest amountIn wins). QuoterV2 functions
 * are non-view but return through eth_call, so simulateContract is the right call.
 * Returns null when no pool quotes — the UI shows "no liquidity" rather than guessing.
 */
export async function quoteExactOutput(
  client: PublicClient,
  tokenIn: Address,
  tokenOut: Address,
  amountOut: bigint,
): Promise<Quote | null> {
  if (!uniswap) return null;
  const results = await Promise.all(
    FEE_TIERS.map(async (fee) => {
      try {
        const { result } = await client.simulateContract({
          address: uniswap.quoterV2,
          abi: quoterV2Abi,
          functionName: "quoteExactOutputSingle",
          args: [{ tokenIn, tokenOut, amount: amountOut, fee, sqrtPriceLimitX96: 0n }],
        });
        return { fee, amountIn: result[0] };
      } catch {
        return null; // no pool at this tier, or not enough liquidity
      }
    }),
  );
  let best: { fee: number; amountIn: bigint } | null = null;
  for (const r of results) if (r && (!best || r.amountIn < best.amountIn)) best = r;
  if (!best) return null;
  return { ...best, amountInMax: best.amountIn + (best.amountIn * SLIPPAGE_BPS) / 10_000n };
}
