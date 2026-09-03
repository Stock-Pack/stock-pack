"use client";

import { useQuery } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { decodeEventLog, erc20Abi, isAddress, parseUnits } from "viem";
import { useAccount, usePublicClient, useReadContracts, useWriteContract } from "wagmi";

import { stockPackAbi } from "@/lib/abi/stockPack";
import { ApprovalChecklist, type BasketEntry } from "@/components/ApprovalChecklist";
import { BuyPanel } from "@/components/BuyPanel";
import { LiveCardPreview } from "@/components/LiveCardPreview";
import { chain, deployment, isDeployed } from "@/lib/contracts";
import { fetchRegistryTokens, fetchWalletTokens, mergeTokens } from "@/lib/discovery";
import { formatAmount } from "@/lib/display";
import { listedTokens, type ListedToken } from "@/lib/tokenlist";

const MAX_BASKET = 16;
const MAX_NAME_BYTES = 31;

type Selected = { token: ListedToken; amountStr: string };

export default function CreatePage() {
  const router = useRouter();
  const { address, isConnected } = useAccount();
  const client = usePublicClient();

  // catalog, in trust order: curated list → Robinhood registry (mainnet, gated) →
  // tokens the user added by address → whatever the explorer says the wallet holds
  const [extraTokens, setExtraTokens] = useState<ListedToken[]>([]);
  const { data: registryTokens } = useQuery({
    queryKey: ["registry"],
    queryFn: fetchRegistryTokens,
    staleTime: 5 * 60_000,
  });
  const { data: walletTokens, isFetching: discovering } = useQuery({
    queryKey: ["walletTokens", address],
    queryFn: () => fetchWalletTokens(address!).catch(() => [] as ListedToken[]),
    enabled: Boolean(address),
    staleTime: 30_000,
    refetchInterval: 30_000,
  });
  const tokens = useMemo(
    () => mergeTokens(listedTokens(), registryTokens ?? [], extraTokens, walletTokens ?? []),
    [registryTokens, extraTokens, walletTokens],
  );

  const [selected, setSelected] = useState<Selected[]>([]);
  const [name, setName] = useState("");
  const [unlimited, setUnlimited] = useState(false);
  const [approvalsReady, setApprovalsReady] = useState(false);
  const [minting, setMinting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { writeContractAsync } = useWriteContract();

  const nameBytes = new TextEncoder().encode(name).length;

  // strictly-ascending order is a contract requirement; sort once, reuse everywhere
  const entries: BasketEntry[] = useMemo(() => {
    const parsed = selected
      .map((s) => {
        try {
          const amount = parseUnits(s.amountStr || "0", s.token.decimals);
          return amount > 0n
            ? { address: s.token.address, symbol: s.token.symbol, decimals: s.token.decimals, amount }
            : null;
        } catch {
          return null;
        }
      })
      .filter(Boolean) as BasketEntry[];
    return parsed.sort((a, b) => (BigInt(a.address) < BigInt(b.address) ? -1 : 1));
  }, [selected]);

  const valid =
    entries.length > 0 &&
    entries.length === selected.length &&
    entries.length <= MAX_BASKET &&
    nameBytes > 0 &&
    nameBytes <= MAX_NAME_BYTES;

  const { data: balanceReads, refetch: refetchBalances } = useReadContracts({
    allowFailure: true,
    contracts: tokens.map((t) => ({
      address: t.address,
      abi: erc20Abi,
      functionName: "balanceOf" as const,
      args: [address ?? "0x0000000000000000000000000000000000000000"] as const,
    })),
    query: { enabled: Boolean(address), refetchInterval: 5_000 },
  });

  const balances = useMemo(() => {
    const m = new Map<string, bigint>();
    tokens.forEach((t, i) => {
      const r = balanceReads?.[i];
      if (r?.status === "success") m.set(t.address.toLowerCase(), r.result as bigint);
    });
    return m;
  }, [tokens, balanceReads]);

  // what the user can actually bundle right now: held tokens, biggest position first
  const held = useMemo(
    () =>
      tokens
        .map((t) => ({ t, bal: balances.get(t.address.toLowerCase()) ?? 0n }))
        .filter((x) => x.bal > 0n)
        .sort((a, b) => {
          const av = Number(a.bal) / 10 ** a.t.decimals;
          const bv = Number(b.bal) / 10 ** b.t.decimals;
          return bv - av;
        }),
    [tokens, balances],
  );

  function toggle(token: ListedToken) {
    setSelected((cur) =>
      cur.some((s) => s.token.address === token.address)
        ? cur.filter((s) => s.token.address !== token.address)
        : cur.length < MAX_BASKET
          ? [...cur, { token, amountStr: "1" }]
          : cur,
    );
  }

  async function mint() {
    if (!valid || !client) return;
    setMinting(true);
    setError(null);
    try {
      const hash = await writeContractAsync({
        address: deployment.stockPack,
        abi: stockPackAbi,
        functionName: "pack",
        args: [name, entries.map((e) => e.address), entries.map((e) => e.amount)],
      });
      const receipt = await client.waitForTransactionReceipt({ hash });
      let tokenId: bigint | null = null;
      for (const log of receipt.logs) {
        try {
          const ev = decodeEventLog({ abi: stockPackAbi, data: log.data, topics: log.topics });
          if (ev.eventName === "Packed") tokenId = (ev.args as { tokenId: bigint }).tokenId;
        } catch {
          /* other contracts' logs */
        }
      }
      // no explicit /api/sync ping (cron-only now): queryBundles() syncs on every read
      router.push(tokenId !== null ? `/bundle/${tokenId}` : "/my");
    } catch (e) {
      setError(shortError(e));
      setMinting(false);
    }
  }

  if (!isDeployed) {
    return <div className="page"><p className="panel px-4 py-6 text-muted">Contracts are not deployed on the configured network yet.</p></div>;
  }

  return (
    <div className="page grid gap-10 lg:grid-cols-[minmax(0,1fr)_320px] lg:gap-14">
      <div className="space-y-8">
        <div>
          <p className="eyebrow">Create</p>
          <h1 className="page-title mt-3">Pack a basket.</h1>
          <p className="mt-3 max-w-xl text-muted">
            Pick up to {MAX_BASKET} tokens from your wallet, set amounts, name it, seal it. The basket is frozen at
            mint and redeemable only by whoever holds the card.
          </p>
        </div>

        {/* 1 · what you hold — the only things that can go into a bundle */}
        <div>
          <div className="mb-2 flex items-baseline justify-between gap-2">
            <h2 className="step">01 · Pick from your wallet</h2>
            {isConnected && (
              <span className="text-[11px] text-muted">
                {discovering ? "scanning wallet…" : `${held.length} token${held.length === 1 ? "" : "s"} found`}
              </span>
            )}
          </div>
          {!isConnected ? (
            <p className="text-xs text-muted">Connect a wallet to see the stocks and coins you can bundle.</p>
          ) : held.length === 0 ? (
            <p className="border border-dashed border-line p-4 text-xs text-muted">
              {discovering
                ? "Scanning your wallet…"
                : "No bundle-able tokens in this wallet yet — buy some below, or add a token you already hold by address."}
            </p>
          ) : (
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {held.map(({ t, bal }) => {
                const on = selected.some((s) => s.token.address === t.address);
                return (
                  <button
                    key={t.address}
                    onClick={() => toggle(t)}
                    className={`flex items-center justify-between gap-2 border p-3 text-left transition-colors ${
                      on ? "border-ink bg-raise" : "border-line bg-card hover:border-ink"
                    }`}
                  >
                    <span className="min-w-0">
                      <span className="block truncate font-mono font-semibold">
                        {t.symbol}
                        {t.real && (
                          <span className="ml-1 bg-[var(--color-danger)] px-1 text-[10px] text-[var(--color-danger)]">REAL</span>
                        )}
                        {!t.verified && (
                          <span className="ml-1 bg-raise px-1 text-[10px] text-accent-ink">
                            UNVERIFIED
                          </span>
                        )}
                      </span>
                      <span className="block truncate text-[10px] uppercase tracking-wider text-muted">
                        {t.name ? `${t.name} · ` : ""}
                        {t.category}
                      </span>
                    </span>
                    <span className="shrink-0 font-mono text-xs text-muted">{formatAmount(bal, t.decimals)}</span>
                  </button>
                );
              })}
            </div>
          )}
        </div>

        {/* buy more / add by address */}
        {isConnected && (
          <div className="space-y-3">
            <BuyPanel tokens={tokens} balances={balances} onBought={() => refetchBalances()} />
            <AddByAddress
              known={tokens}
              onAdd={(t) => setExtraTokens((cur) => [...cur, t])}
            />
          </div>
        )}

        {/* 2 · amounts */}
        {selected.length > 0 && (
          <div>
            <h2 className="step mb-3">02 · Set amounts</h2>
            <div className="space-y-2">
              {selected.map((s) => {
                const bal = balances.get(s.token.address.toLowerCase()) ?? 0n;
                return (
                  <div key={s.token.address} className="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <span className="w-16 shrink-0 truncate font-mono text-sm sm:w-20">{s.token.symbol}</span>
                    <input
                      value={s.amountStr}
                      onChange={(e) =>
                        setSelected((cur) =>
                          cur.map((x) => (x.token.address === s.token.address ? { ...x, amountStr: e.target.value } : x)),
                        )
                      }
                      inputMode="decimal"
                      className="field w-32 sm:w-40"
                    />
                    <button
                      onClick={() =>
                        setSelected((cur) =>
                          cur.map((x) =>
                            x.token.address === s.token.address
                              ? { ...x, amountStr: fullUnits(bal, s.token.decimals) }
                              : x,
                          ),
                        )
                      }
                      className="text-xs text-muted hover:text-ink"
                    >
                      max {formatAmount(bal, s.token.decimals)}
                    </button>
                    {(() => {
                      try {
                        const v = parseUnits(s.amountStr || "0", s.token.decimals);
                        if (v === 0n) return <span className="text-xs text-[var(--color-danger)]">must be &gt; 0</span>;
                        if (v > bal) return <span className="text-xs text-[var(--color-danger)]">more than you hold</span>;
                        if (formatAmount(v, s.token.decimals) === "<0.000001")
                          return <span className="text-xs text-accent-ink">tiny — card shows &lt;0.000001</span>;
                        return null;
                      } catch {
                        return <span className="text-xs text-[var(--color-danger)]">invalid</span>;
                      }
                    })()}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* 3 · name */}
        <div>
          <h2 className="step mb-3">03 · Name it</h2>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="The Big Tech Bundle"
            className="field max-w-md"
          />
          <span
            className={`mt-1 block text-xs sm:mt-0 sm:ml-3 sm:inline ${nameBytes > MAX_NAME_BYTES ? "text-[var(--color-danger)]" : "text-muted"}`}
          >
            {nameBytes}/{MAX_NAME_BYTES} bytes
          </span>
        </div>

        {/* 4 · approvals */}
        {valid && (
          <div>
            <h2 className="step mb-3">04 · Approve</h2>
            <label className="mb-2 flex items-center gap-2 text-xs text-muted">
              <input type="checkbox" checked={unlimited} onChange={(e) => setUnlimited(e.target.checked)} />
              unlimited approvals (fewer transactions next time, standing allowance risk)
            </label>
            <ApprovalChecklist entries={entries} unlimited={unlimited} onReady={setApprovalsReady} />
          </div>
        )}

        {/* mint */}
        <div>
          <button
            onClick={mint}
            disabled={!isConnected || !valid || !approvalsReady || minting}
            className="btn btn-primary w-full sm:w-auto"
          >
            {minting ? "Sealing…" : "Seal the bundle"}
          </button>
          {!isConnected && <p className="mt-2 text-xs text-muted">Connect a wallet to mint.</p>}
          {error && <p className="mt-2 max-w-md break-words text-xs text-[var(--color-danger)]">{error}</p>}
        </div>
      </div>

      {/* live preview via the on-chain renderer */}
      <div className="lg:sticky lg:top-20 lg:self-start">
        <h2 className="eyebrow mb-3">Preview · rendered on-chain</h2>
        <LiveCardPreview
          tokens={entries.map((e) => e.address)}
          amounts={entries.map((e) => e.amount)}
          name={name}
        />
      </div>
    </div>
  );
}

/**
 * The escrow accepts any standard ERC-20, so a holder of something not in the curated
 * list can still bundle it. Resolved on-chain (symbol/decimals) and flagged UNVERIFIED —
 * the list is the only defense against counterfeit tickers, so the badge stays loud.
 */
function AddByAddress({ known, onAdd }: { known: ListedToken[]; onAdd: (t: ListedToken) => void }) {
  const [input, setInput] = useState("");
  const addr = isAddress(input.trim()) ? (input.trim() as `0x${string}`) : null;
  const already = addr !== null && known.some((t) => t.address.toLowerCase() === addr.toLowerCase());

  const { data, isFetching } = useReadContracts({
    allowFailure: true,
    contracts: addr
      ? [
          { address: addr, abi: erc20Abi, functionName: "symbol" as const },
          { address: addr, abi: erc20Abi, functionName: "decimals" as const },
        ]
      : [],
    query: { enabled: addr !== null && !already },
  });
  const symbol = data?.[0]?.status === "success" ? String(data[0].result) : null;
  const decimals = data?.[1]?.status === "success" ? Number(data[1].result) : null;
  const resolved = addr && symbol && decimals !== null;

  return (
    <div className="panel p-4">
      <h3 className="step mb-3">Add any token by address</h3>
      <div className="flex flex-wrap gap-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="0x… ERC-20 contract address"
          className="field min-w-0 flex-1"
        />
        <button
          disabled={!resolved || already}
          onClick={() => {
            if (!resolved) return;
            onAdd({
              address: addr,
              symbol: symbol.slice(0, 11),
              decimals,
              verified: false,
              real: false,
              category: "other",
              hasFaucet: false,
            });
            setInput("");
          }}
          className="btn btn-ghost btn-sm"
        >
          Add
        </button>
      </div>
      <p className="mt-2 text-xs text-muted">
        {input && !addr
          ? "Not a valid address."
          : already
            ? "Already in your list."
            : isFetching
              ? "Looking up…"
              : resolved
                ? `Found ${symbol} (${decimals} decimals). It will be marked UNVERIFIED — check the address yourself.`
                : addr
                  ? `No ERC-20 at that address on ${chain.name}. Addresses from other networks (Ethereum, Base, …) won't work — a token has to live on this chain to be bundled. `
                  : `Only tokens you already hold on ${chain.name} will appear in step 1.`}
        {addr && !resolved && !isFetching && chain.blockExplorers?.default.url && (
          <a
            href={`${chain.blockExplorers.default.url}/address/${addr}`}
            target="_blank"
            rel="noopener noreferrer"
            className="link-arrow"
          >
            Check it on the explorer ↗
          </a>
        )}
      </p>
    </div>
  );
}

function fullUnits(v: bigint, decimals: number): string {
  const s = v.toString().padStart(decimals + 1, "0");
  const whole = s.slice(0, s.length - decimals);
  const frac = s.slice(s.length - decimals).replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : whole;
}

function shortError(e: unknown): string {
  const s = String((e as { shortMessage?: string })?.shortMessage ?? e);
  return s.length > 300 ? s.slice(0, 300) + "…" : s;
}
