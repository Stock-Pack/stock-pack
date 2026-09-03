"use client";

import { useEffect } from "react";
import { erc20Abi } from "viem";
import { useAccount, useReadContracts, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { deployment } from "@/lib/contracts";
import { formatAmount } from "@/lib/display";

export type BasketEntry = { address: `0x${string}`; symbol: string; decimals: number; amount: bigint };

/** Sequential per-token approval flow (the tier every wallet supports). Exact-amount
 *  approvals by default — no standing unlimited allowances unless the user opts in. */
export function ApprovalChecklist({
  entries,
  unlimited,
  onReady,
}: {
  entries: BasketEntry[];
  unlimited: boolean;
  onReady: (ready: boolean) => void;
}) {
  const { address } = useAccount();
  const { data: allowances, refetch } = useReadContracts({
    allowFailure: true,
    contracts: entries.map((e) => ({
      address: e.address,
      abi: erc20Abi,
      functionName: "allowance" as const,
      args: [address ?? "0x0000000000000000000000000000000000000000", deployment.stockPack] as const,
    })),
    query: { enabled: Boolean(address) && entries.length > 0, refetchInterval: 4_000 },
  });

  const { writeContract, data: txHash, isPending, variables } = useWriteContract();
  const { isSuccess: txMined } = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (txMined) refetch();
  }, [txMined, refetch]);

  const states = entries.map((e, i) => {
    const a = allowances?.[i];
    const current = a?.status === "success" ? (a.result as bigint) : 0n;
    return { ...e, approved: current >= e.amount };
  });
  const allApproved = states.length > 0 && states.every((s) => s.approved);

  useEffect(() => {
    onReady(allApproved);
  }, [allApproved, onReady]);

  if (!address || entries.length === 0) return null;

  return (
    <div className="space-y-2">
      <h3 className="text-sm font-semibold text-ink">Approvals</h3>
      {states.map((s) => (
        <div key={s.address} className="flex flex-wrap items-center justify-between gap-2 border border-line px-3 py-2">
          <span className="min-w-0 font-mono text-sm break-all">
            {s.symbol} · {formatAmount(s.amount, s.decimals)}
          </span>
          {s.approved ? (
            <span className="text-sm text-emerald-400">✓ approved</span>
          ) : (
            <button
              onClick={() =>
                writeContract({
                  address: s.address,
                  abi: erc20Abi,
                  functionName: "approve",
                  args: [deployment.stockPack, unlimited ? 2n ** 256n - 1n : s.amount],
                })
              }
              disabled={isPending}
              className="btn btn-ghost btn-sm"
            >
              {isPending && (variables?.address as string) === s.address ? "confirm…" : "Approve"}
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
