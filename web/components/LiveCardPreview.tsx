"use client";

import { useAccount, useReadContract } from "wagmi";

import { rendererAbi } from "@/lib/abi/renderer";
import { deployment } from "@/lib/contracts";

/** Renders the create page's preview through the EXACT on-chain code path
 *  (StockPackRenderer.previewSVG via eth_call) — what you see is what OpenSea gets. */
export function LiveCardPreview({
  tokens,
  amounts,
  name,
}: {
  tokens: `0x${string}`[];
  amounts: bigint[];
  name: string;
}) {
  const { address } = useAccount();
  const enabled = tokens.length > 0 && tokens.length === amounts.length && name.length > 0 && Boolean(address);

  const { data: svg, isLoading, isError } = useReadContract({
    address: deployment.renderer,
    abi: rendererAbi,
    functionName: "previewSVG",
    args: [tokens, amounts, name, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled, staleTime: 5_000 },
  });

  if (!enabled) {
    return (
      <div className="mx-auto flex aspect-square w-full max-w-[340px] items-center justify-center border border-dashed border-line px-4 text-center text-sm text-muted lg:mx-0">
        Pick tokens, amounts
        <br />
        and a name to preview
      </div>
    );
  }
  if (isError) {
    return (
      <div className="mx-auto flex aspect-square w-full max-w-[340px] items-center justify-center border border-dashed border-[var(--color-danger)] px-4 text-center text-sm text-[var(--color-danger)] lg:mx-0">
        Preview unavailable — the RPC call to the renderer failed. Check the network connection to the chain.
      </div>
    );
  }
  if (isLoading || !svg) {
    return <div className="mx-auto aspect-square w-full max-w-[340px] animate-pulse bg-raise lg:mx-0" />;
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={`data:image/svg+xml;utf8,${encodeURIComponent(svg as string)}`}
      alt="Bundle preview card"
      className="mx-auto w-full max-w-[340px] lg:mx-0"
    />
  );
}
