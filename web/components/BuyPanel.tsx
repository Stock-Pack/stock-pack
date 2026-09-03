"use client";

import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { erc20Abi, formatUnits, isAddress, parseUnits } from "viem";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";

import { mockStockTokenAbi } from "@/lib/abi/mockStockToken";
import { chain, network } from "@/lib/contracts";
import { formatAmount } from "@/lib/display";
import type { ListedToken } from "@/lib/tokenlist";
import { quoteExactOutput, swapEnabled, swapRouter02Abi, uniswap, type Quote } from "@/lib/uniswap";

/** MockStockToken.MAX_MINT — one order per tx on local/testnet. */
const MOCK_MAX_PER_ORDER = 1_000n;

type Order = { token: ListedToken; qtyStr: string; pay: ListedToken | null };

/**
 * Search the catalog, say how many you want, confirm, and the tokens land in your wallet
 * so they can be bundled. Two acquisition backends behind one UI:
 *   - local/testnet: MockStockToken.mint(to, amount) — free demo tokens, capped per order.
 *   - mainnet:       Uniswap V3 exact-output swap (QuoterV2 → approve pay token → SwapRouter02).
 * Nothing here touches the escrow; it only fills the user's wallet.
 */
export function BuyPanel({
  tokens,
  balances,
  onBought,
}: {
  tokens: ListedToken[];
  balances: Map<string, bigint>;
  onBought: () => void;
}) {
  const { address } = useAccount();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [query, setQuery] = useState("");
  const [order, setOrder] = useState<Order | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const payTokens = useMemo(() => tokens.filter((t) => t.real && t.category === "coin"), [tokens]);

  // With no query: everything you can get from here (mint / swap / external faucet).
  // With a query: the whole catalog, so a search for something you already hold — or that
  // simply can't be bought here — says so instead of pretending it doesn't exist.
  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return tokens.filter((t) => acquisition(t) !== "none");
    return tokens.filter(
      (t) =>
        t.symbol.toLowerCase().includes(q) ||
        (t.name?.toLowerCase().includes(q) ?? false) ||
        t.address.toLowerCase().startsWith(q),
    );
  }, [tokens, query]);

  const qty = useMemo(() => {
    if (!order) return null;
    try {
      const v = parseUnits(order.qtyStr || "0", order.token.decimals);
      return v > 0n ? v : null;
    } catch {
      return null;
    }
  }, [order]);

  const isMock = order?.token.hasFaucet ?? false;
  const overCap = isMock && qty !== null && qty > MOCK_MAX_PER_ORDER * 10n ** BigInt(order!.token.decimals);

  // live quote for real tokens — keyed on the order so every edit re-quotes; 10s freshness
  const wantQuote = Boolean(order && !isMock && client && qty && order.pay);
  const { data: quote, isFetching: quoting } = useQuery({
    queryKey: ["quote", order?.pay?.address, order?.token.address, qty?.toString()],
    queryFn: async (): Promise<Quote | "none"> => {
      const q = await quoteExactOutput(client!, order!.pay!.address, order!.token.address, qty!).catch(() => null);
      return q ?? "none";
    },
    enabled: wantQuote,
    staleTime: 10_000,
    refetchInterval: 10_000,
  });

  function startOrder(token: ListedToken) {
    setError(null);
    setDone(null);
    const pay = payTokens.find((p) => p.address !== token.address) ?? null;
    setOrder({ token, qtyStr: token.hasFaucet ? "100" : "1", pay });
  }

  async function confirm() {
    if (!order || !qty || !address || !client) return;
    setBusy("Confirm in your wallet…");
    setError(null);
    try {
      if (isMock) {
        const hash = await writeContractAsync({
          address: order.token.address,
          abi: mockStockTokenAbi,
          functionName: "mint",
          args: [address, qty],
        });
        setBusy("Minting…");
        await client.waitForTransactionReceipt({ hash });
      } else {
        if (!uniswap || !order.pay || !quote || quote === "none") throw new Error("No quote available");
        const payBal = balances.get(order.pay.address.toLowerCase()) ?? 0n;
        if (payBal < quote.amountInMax) {
          throw new Error(
            `Not enough ${order.pay.symbol}: need up to ${fmt(quote.amountInMax, order.pay.decimals)}, have ${fmt(payBal, order.pay.decimals)}`,
          );
        }
        const allowance = await client.readContract({
          address: order.pay.address,
          abi: erc20Abi,
          functionName: "allowance",
          args: [address, uniswap.swapRouter02],
        });
        if (allowance < quote.amountInMax) {
          setBusy(`Approve ${order.pay.symbol} in your wallet…`);
          const approveHash = await writeContractAsync({
            address: order.pay.address,
            abi: erc20Abi,
            functionName: "approve",
            args: [uniswap.swapRouter02, quote.amountInMax], // exact-amount, no standing allowance
          });
          await client.waitForTransactionReceipt({ hash: approveHash });
        }
        setBusy("Confirm the swap in your wallet…");
        const hash = await writeContractAsync({
          address: uniswap.swapRouter02,
          abi: swapRouter02Abi,
          functionName: "exactOutputSingle",
          args: [
            {
              tokenIn: order.pay.address,
              tokenOut: order.token.address,
              fee: quote.fee,
              recipient: address,
              amountOut: qty,
              amountInMaximum: quote.amountInMax,
              sqrtPriceLimitX96: 0n,
            },
          ],
        });
        setBusy("Swapping…");
        await client.waitForTransactionReceipt({ hash });
      }
      setDone(`${fmt(qty, order.token.decimals)} ${order.token.symbol} added to your wallet`);
      setOrder(null);
      onBought();
    } catch (e) {
      setError(shortError(e));
    } finally {
      setBusy(null);
    }
  }

  if (!address) return null;

  return (
    <div className="border border-line p-4">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-semibold text-ink">Buy stocks &amp; coins</h3>
        <span className="text-[11px] text-muted">
          {swapEnabled ? "Swapped on Uniswap, delivered to your wallet" : "Free demo tokens on this network — nothing costs real money"}
        </span>
      </div>

      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search by ticker, company name, or address…"
        className="mb-3 w-full border border-line bg-card px-3 py-2 text-sm outline-none focus:border-ink"
      />

      {results.length === 0 ? (
        <p className="text-xs text-muted">
          {isAddress(query.trim())
            ? `That address isn't in the catalog. If it's an ERC-20 on ${chain.name}, add it with "Add any token by address" below — addresses from other networks can't be bundled here.`
            : swapEnabled
              ? `Nothing matches “${query}”. Robinhood hasn't tokenized it, or it's a coin without a listed Uniswap pool — you can still add anything you already hold by address below.`
              : `Nothing matches “${query}”. On ${chain.name} only the demo tokens and Robinhood's five faucet stocks exist — hold something else? Add it by address below.`}
        </p>
      ) : (
        <ul className="max-h-64 divide-y divide-line-soft overflow-y-auto">
          {results.map((t) => {
            const bal = balances.get(t.address.toLowerCase());
            const how = acquisition(t);
            return (
              <li key={t.address} className="flex items-center justify-between gap-3 py-2">
                <div className="flex min-w-0 items-center gap-2">
                  {t.logoUrl && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={t.logoUrl} alt="" width={24} height={24} className="h-6 w-6 shrink-0" />
                  )}
                  <div className="min-w-0">
                    <span className="font-mono font-semibold">{t.symbol}</span>
                    <span className="ml-2 truncate text-[10px] uppercase tracking-wider text-muted">
                      {t.name ? `${t.name} · ` : ""}
                      {t.category}
                    </span>
                    {t.real && <span className="ml-1 bg-[var(--color-danger)] px-1 text-[10px] text-[var(--color-danger)]">REAL</span>}
                    {!t.verified && (
                      <span className="ml-1 bg-raise px-1 text-[10px] text-accent-ink">UNVERIFIED</span>
                    )}
                    <div className="text-xs text-muted">
                      in wallet: {bal !== undefined ? fmt(bal, t.decimals) : "—"}
                    </div>
                  </div>
                </div>
                {how === "faucet" ? (
                  <a
                    href={t.faucetUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="shrink-0 bg-raise px-3 py-1 text-xs text-ink hover:bg-line"
                    title="Robinhood's testnet faucet: 5 of each stock per day"
                  >
                    Get free ↗
                  </a>
                ) : how === "none" ? (
                  <span className="shrink-0 text-[11px] text-muted">
                    {bal !== undefined && bal > 0n ? "in wallet — pick it above" : "not sold here"}
                  </span>
                ) : (
                  <button
                    onClick={() => startOrder(t)}
                    disabled={busy !== null}
                    className="shrink-0 bg-raise px-3 py-1 text-xs text-ink hover:bg-line disabled:opacity-40"
                  >
                    {how === "mint" ? "Get" : "Buy"}
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {order && (
        <div className="mt-4 border border-ink/40 bg-raise p-3">
          <div className="mb-2 text-sm font-semibold">
            Buy <span className="font-mono">{order.token.symbol}</span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <label className="text-xs text-muted">How many</label>
            <input
              value={order.qtyStr}
              onChange={(e) => setOrder({ ...order, qtyStr: e.target.value })}
              inputMode="decimal"
              className="w-28 border border-line bg-card px-3 py-1.5 font-mono text-sm outline-none focus:border-ink"
            />
            {!isMock && payTokens.length > 1 && (
              <>
                <label className="text-xs text-muted">pay with</label>
                <select
                  value={order.pay?.address ?? ""}
                  onChange={(e) =>
                    setOrder({ ...order, pay: payTokens.find((p) => p.address === e.target.value) ?? null })
                  }
                  className="border border-line bg-card px-2 py-1.5 text-sm outline-none"
                >
                  {payTokens
                    .filter((p) => p.address !== order.token.address)
                    .map((p) => (
                      <option key={p.address} value={p.address}>
                        {p.symbol}
                      </option>
                    ))}
                </select>
              </>
            )}
          </div>

          <div className="mt-2 text-xs text-muted">
            {qty === null ? (
              <span className="text-[var(--color-danger)]">enter an amount &gt; 0</span>
            ) : overCap ? (
              <span className="text-[var(--color-danger)]">max {MOCK_MAX_PER_ORDER.toString()} per order on this network</span>
            ) : isMock ? (
              <>
                Free testnet mint — {fmt(qty, order.token.decimals)} {order.token.symbol} will be sent to your wallet.
              </>
            ) : quoting ? (
              "Getting a quote…"
            ) : quote === "none" ? (
              <span className="text-[var(--color-danger)]">No Uniswap pool with enough liquidity for this size.</span>
            ) : quote && order.pay ? (
              <>
                Cost ≈ <span className="font-mono text-ink">{fmt(quote.amountIn, order.pay.decimals)} {order.pay.symbol}</span>
                {" "}(max {fmt(quote.amountInMax, order.pay.decimals)} with 0.5% slippage · {order.token.symbol}/{order.pay.symbol} {quote.fee / 10_000}% pool)
              </>
            ) : (
              "Select a pay token"
            )}
          </div>

          <div className="mt-3 flex flex-wrap gap-2">
            <button
              onClick={confirm}
              disabled={busy !== null || qty === null || overCap || (!isMock && (!quote || quote === "none" || quoting))}
              className="btn btn-primary btn-sm"
            >
              {busy ?? (isMock ? "Confirm & mint" : "Confirm & buy")}
            </button>
            <button
              onClick={() => setOrder(null)}
              disabled={busy !== null}
              className="px-3 py-1.5 text-sm text-muted hover:text-ink disabled:opacity-40"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {done && <p className="mt-3 text-xs text-emerald-400">✓ {done}</p>}
      {error && <p className="mt-3 max-w-md break-words text-xs text-[var(--color-danger)]">{error}</p>}
      {network === "mainnet" && !swapEnabled && (
        <p className="mt-3 text-xs text-muted">Buying is not available on this network yet.</p>
      )}
    </div>
  );
}

/** How this site can put the token in the user's wallet, if at all. */
function acquisition(t: ListedToken): "mint" | "swap" | "faucet" | "none" {
  if (t.hasFaucet) return "mint";
  if (swapEnabled && t.real) return "swap";
  if (t.faucetUrl) return "faucet";
  return "none";
}

function fmt(v: bigint, decimals: number): string {
  // card-style truncation for ≥0.01, full precision for dust so a quote is never shown as "0"
  const s = formatAmount(v, decimals);
  return s === "<0.000001" ? formatUnits(v, decimals) : s;
}

function shortError(e: unknown): string {
  const s = String((e as { shortMessage?: string })?.shortMessage ?? (e as Error)?.message ?? e);
  return s.length > 240 ? s.slice(0, 240) + "…" : s;
}
