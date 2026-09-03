"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useAccount, usePublicClient, useReadContracts, useWriteContract } from "wagmi";

import { stockPackAbi } from "@/lib/abi/stockPack";
import { BundleCard } from "@/components/BundleCard";
import { deployment } from "@/lib/contracts";
import type { BundleDoc } from "@/lib/db";
import { formatAmount } from "@/lib/display";
import { listedTokens } from "@/lib/tokenlist";

export default function MyPage() {
  const { address, isConnected } = useAccount();

  const { data, isLoading, refetch } = useQuery({
    queryKey: ["my-bundles", address],
    enabled: Boolean(address),
    refetchInterval: 15_000,
    queryFn: async () => {
      const res = await fetch(`/api/bundles?owner=${address}&limit=50`);
      if (!res.ok) throw new Error(await res.text());
      return (await res.json()).bundles as BundleDoc[];
    },
  });

  if (!isConnected)
    return (
      <div className="page">
        <p className="panel px-6 py-16 text-center text-muted">Connect a wallet to see your bundles.</p>
      </div>
    );

  return (
    <div className="page space-y-14">
      <div>
        <p className="eyebrow">Portfolio</p>
        <h1 className="page-title mt-3">Bundles you hold.</h1>
        {isLoading ? (
          <div className="mt-8 grid auto-rows-fr gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            <div className="h-72 animate-pulse border border-line bg-card" />
          </div>
        ) : !data || data.length === 0 ? (
          <p className="panel mt-8 px-6 py-10 text-muted">No live bundles held by this wallet.</p>
        ) : (
          <div className="mt-8 grid auto-rows-fr gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {data.map((b) => (
              <BundleCard key={b._id} bundle={b} art />
            ))}
          </div>
        )}
      </div>
      <ClaimsPanel onClaimed={() => refetch()} />
    </div>
  );
}

/** Pending per-token claims from emergencyUnpack — pull-pattern withdrawals. */
function ClaimsPanel({ onClaimed }: { onClaimed: () => void }) {
  const { address } = useAccount();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();
  const [busyToken, setBusyToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const tokens = listedTokens();

  const { data: claims, refetch } = useReadContracts({
    allowFailure: true,
    contracts: tokens.map((t) => ({
      address: deployment.stockPack,
      abi: stockPackAbi,
      functionName: "claimable" as const,
      args: [address ?? "0x0000000000000000000000000000000000000000", t.address] as const,
    })),
    query: { enabled: Boolean(address), refetchInterval: 10_000 },
  });

  const pending = tokens
    .map((t, i) => ({
      token: t,
      amount: claims?.[i]?.status === "success" ? (claims[i].result as bigint) : 0n,
    }))
    .filter((c) => c.amount > 0n);

  if (pending.length === 0) return null;

  async function claim(tokenAddr: `0x${string}`) {
    if (!client) return;
    setBusyToken(tokenAddr);
    setError(null);
    try {
      const hash = await writeContractAsync({
        address: deployment.stockPack,
        abi: stockPackAbi,
        functionName: "claim",
        args: [tokenAddr, address!],
      });
      await client.waitForTransactionReceipt({ hash });
      refetch();
      onClaimed();
    } catch (e) {
      setError(String((e as { shortMessage?: string })?.shortMessage ?? e).slice(0, 200));
    }
    setBusyToken(null);
  }

  return (
    <div className="panel border-l-2 border-l-accent p-4">
      <h2 className="step">Pending claims</h2>
      <p className="mini mt-2 max-w-2xl">
        From emergency unpacks — withdraw each token individually. If a token is still frozen by its issuer, its claim
        simply waits; it can never be lost.
      </p>
      <div className="mt-3 space-y-2">
        {pending.map((c) => (
          <div key={c.token.address} className="flex flex-wrap items-center justify-between gap-2 border border-line px-3 py-2">
            <span className="min-w-0 font-mono text-sm break-all">
              {c.token.symbol} · {formatAmount(c.amount, c.token.decimals)}
            </span>
            <button
              onClick={() => claim(c.token.address)}
              disabled={busyToken !== null}
              className="btn btn-primary btn-sm"
            >
              {busyToken === c.token.address ? "claiming…" : "Claim"}
            </button>
          </div>
        ))}
      </div>
      {error && <p className="mt-2 text-xs text-[var(--color-danger)]">{error}</p>}
    </div>
  );
}
