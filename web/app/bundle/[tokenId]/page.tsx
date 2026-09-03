"use client";

import { use, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useAccount, usePublicClient, useReadContracts, useWriteContract } from "wagmi";

import { CardTilt } from "@/components/CardTilt";
import { stockPackAbi } from "@/lib/abi/stockPack";
import { chain, deployment, network, openSeaAssetUrl } from "@/lib/contracts";
import { formatAmount, sealedDate, shortAddress } from "@/lib/display";
import { findListed } from "@/lib/tokenlist";

const uiMultiplierAbi = [
  { type: "function", name: "uiMultiplier", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

export default function BundlePage({ params }: { params: Promise<{ tokenId: string }> }) {
  const { tokenId: tokenIdStr } = use(params);
  const tokenId = BigInt(tokenIdStr.match(/^\d{1,10}$/) ? tokenIdStr : "0");
  const router = useRouter();
  const { address } = useAccount();
  const client = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [busy, setBusy] = useState(false);
  const [needsEmergency, setNeedsEmergency] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const { data, isLoading, refetch } = useReadContracts({
    allowFailure: true,
    contracts: [
      { address: deployment.stockPack, abi: stockPackAbi, functionName: "getBasket", args: [tokenId] },
      { address: deployment.stockPack, abi: stockPackAbi, functionName: "bundleMeta", args: [tokenId] },
      { address: deployment.stockPack, abi: stockPackAbi, functionName: "ownerOf", args: [tokenId] },
      { address: deployment.stockPack, abi: stockPackAbi, functionName: "tokenURI", args: [tokenId] },
    ],
    query: { enabled: tokenId > 0n },
  });

  const basket = data?.[0]?.status === "success" ? (data[0].result as [readonly `0x${string}`[], readonly bigint[]]) : null;
  const meta = data?.[1]?.status === "success" ? (data[1].result as [string, `0x${string}`, bigint]) : null;
  const owner = data?.[2]?.status === "success" ? (data[2].result as `0x${string}`) : null;
  const uri = data?.[3]?.status === "success" ? (data[3].result as string) : null;

  const imageSrc = useMemo(() => {
    if (!uri) return null;
    try {
      const json = JSON.parse(atob(uri.split(",")[1]));
      const image = json.image;
      // only render the renderer's own inline SVG — never an arbitrary URL from chain data
      return typeof image === "string" && image.startsWith("data:image/svg+xml") ? image : null;
    } catch {
      return null;
    }
  }, [uri]);

  const { data: multipliers } = useReadContracts({
    allowFailure: true,
    contracts: (basket?.[0] ?? []).map((t) => ({ address: t, abi: uiMultiplierAbi, functionName: "uiMultiplier" as const })),
    query: { enabled: Boolean(basket) },
  });

  const isOwner = Boolean(address && owner && address.toLowerCase() === owner.toLowerCase());

  async function redeem(emergency: boolean) {
    if (!client || !address) return;
    setBusy(true);
    setError(null);
    try {
      if (!emergency) {
        try {
          await client.simulateContract({
            address: deployment.stockPack,
            abi: stockPackAbi,
            functionName: "unpack",
            args: [tokenId],
            account: address,
          });
        } catch (e) {
          // a constituent transfer reverts (paused/blocklisted) — surface the escape hatch
          setNeedsEmergency(true);
          setError(`Atomic unpack would fail: ${shortError(e)}`);
          setBusy(false);
          return;
        }
      }
      const hash = await writeContractAsync({
        address: deployment.stockPack,
        abi: stockPackAbi,
        functionName: emergency ? "emergencyUnpack" : "unpack",
        args: [tokenId],
      });
      await client.waitForTransactionReceipt({ hash });
      // no explicit /api/sync ping (cron-only now): queryBundles() syncs on every read
      if (emergency) router.push("/my"); // claims live there
      else refetch();
    } catch (e) {
      setError(shortError(e));
    }
    setBusy(false);
  }

  if (tokenId === 0n) return <div className="page"><p className="panel px-4 py-6 text-muted">Invalid bundle id.</p></div>;
  if (isLoading) return <div className="page"><div className="h-96 animate-pulse border border-line bg-card" /></div>;

  if (!basket || !meta) {
    return (
      <div className="page py-16 text-center">
        <h1 className="page-title">Bundle #{tokenIdStr}</h1>
        <p className="mt-3 text-muted">
          This bundle does not exist on-chain — it was either never minted or has been <b>redeemed</b> (unwrapped) by
          its holder. Redeemed cards are burned and their escrow rows deleted.
        </p>
      </div>
    );
  }

  const [tokens, amounts] = basket;
  const [name, creator, sealedAt] = meta;
  const explorer = chain.blockExplorers?.default.url;
  const osUrl = openSeaAssetUrl(tokenIdStr);

  return (
    <div className="page grid gap-10 lg:grid-cols-[320px_minmax(0,1fr)] lg:gap-14">
      <div className="mx-auto w-full max-w-[300px] lg:mx-0">
        {imageSrc ? (
          <CardTilt>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={imageSrc} alt={`${name} card`} className="block w-full" />
          </CardTilt>
        ) : (
          <div className="aspect-square w-full bg-card" />
        )}
        <div className="mt-3 flex gap-2">
          <button
            onClick={() => {
              navigator.clipboard.writeText(window.location.href).then(() => {
                setCopied(true);
                setTimeout(() => setCopied(false), 1500);
              });
            }}
            className="btn btn-ghost btn-sm flex-1"
          >
            {copied ? "Copied ✓" : "Copy link"}
          </button>
          {osUrl && (
            <a
              href={osUrl}
              target="_blank"
              rel="noreferrer"
              className="btn btn-ghost btn-sm flex-1"
            >
              OpenSea ↗
            </a>
          )}
        </div>
        {network === "mainnet" && (
          <button
            onClick={() => fetch(`/api/refresh/${tokenIdStr}`, { method: "POST" })}
            className="btn btn-ghost btn-sm mt-2 w-full"
          >
            Refresh OpenSea metadata
          </button>
        )}
      </div>

      <div className="min-w-0 space-y-6">
        <div>
          <p className="eyebrow">Bundle</p>
          <h1 className="page-title mt-3 break-words">
            {name} <span className="text-muted">#{tokenIdStr}</span>
          </h1>
          <p className="mini mt-3">
            Sealed {sealedDate(Number(sealedAt))} by{" "}
            <span className="font-mono">{shortAddress(creator)}</span> · held by{" "}
            <span className="font-mono">{owner ? shortAddress(owner) : "—"}</span>
            {isOwner && <span className="ml-1 text-accent-ink">(you)</span>}
          </p>
        </div>

        <div className="panel overflow-x-auto">
          <table className="w-full min-w-[34rem] text-sm">
            <thead className="border-b border-line bg-raise text-left">
              <tr>
                <th className="eyebrow px-4 py-2.5 whitespace-nowrap">Token</th>
                <th className="eyebrow px-4 py-2.5 whitespace-nowrap">Escrowed (raw)</th>
                <th className="eyebrow px-4 py-2.5 whitespace-nowrap">≈ shares (ERC-8056)</th>
                <th className="eyebrow px-4 py-2.5 whitespace-nowrap">Contract</th>
              </tr>
            </thead>
            <tbody className="font-mono">
              {tokens.map((t, i) => {
                const listed = findListed(t);
                const dec = listed?.decimals ?? 18;
                const m = multipliers?.[i];
                const mult = m?.status === "success" ? (m.result as bigint) : null;
                const shares = mult !== null ? formatAmount((amounts[i] * mult) / 10n ** 18n, dec) : "—";
                return (
                  <tr key={t} className="border-b border-line-soft">
                    <td className="px-4 py-2 font-semibold">
                      {listed?.symbol ?? shortAddress(t)}
                      {!listed && (
                        <span className="ml-2 border border-line px-1.5 text-[10px] text-accent-ink">
                          UNVERIFIED — check the address
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-2">{formatAmount(amounts[i], dec)}</td>
                    <td className="px-4 py-2 text-muted">{shares}</td>
                    <td className="px-4 py-2">
                      {explorer ? (
                        <a href={`${explorer}/address/${t}`} target="_blank" rel="noreferrer" className="text-muted hover:text-ink">
                          {shortAddress(t)} ↗
                        </a>
                      ) : (
                        shortAddress(t)
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-muted">
          Raw amounts are the redemption floor — they can never change while this card exists. Tokenized stocks accrue
          corporate-action value via their on-chain uiMultiplier, so the share-equivalent can drift upward while raw
          amounts stay fixed.
        </p>

        {isOwner && (
          <div className="panel p-5">
            <h2 className="step">Redeem</h2>
            <p className="mini mt-3">
              Burn this card and withdraw every escrowed token to your wallet in one transaction.
            </p>
            <div className="mt-3 flex flex-col gap-3 sm:flex-row">
              <button
                onClick={() => redeem(false)}
                disabled={busy}
                className="btn btn-primary"
              >
                {busy ? "Working…" : "Unpack everything"}
              </button>
              {needsEmergency && (
                <button
                  onClick={() => redeem(true)}
                  disabled={busy}
                  className="btn btn-ghost border-[var(--color-danger)] text-[var(--color-danger)] hover:border-[var(--color-danger)]"
                >
                  Emergency unpack
                </button>
              )}
            </div>
            {needsEmergency && (
              <p className="mt-2 text-xs text-muted">
                Emergency unpack burns the card without moving tokens and credits per-token claims you can withdraw
                individually from “My Bundles” — one frozen token can’t trap the rest.
              </p>
            )}
            {error && <p className="mt-2 break-words text-xs text-[var(--color-danger)]">{error}</p>}
          </div>
        )}
      </div>
    </div>
  );
}

function shortError(e: unknown): string {
  const s = String((e as { shortMessage?: string })?.shortMessage ?? e);
  return s.length > 220 ? s.slice(0, 220) + "…" : s;
}
