import { createPublicClient, http, type PublicClient } from "viem";

import { stockPackAbi } from "./abi/stockPack";
import { chain, deployment, serverRpcUrl } from "./contracts";
import { getDb, mongoEnabled, type BundleDoc } from "./db";

const ZERO = "0x0000000000000000000000000000000000000000";
/** Public RPCs cap getLogs ranges; stay well inside. */
const CHUNK = 9_000n;

export function publicClient(): PublicClient {
  return createPublicClient({ chain, transport: http(serverRpcUrl) });
}

/**
 * Incremental event sync into MongoDB. Idempotent: bundles are keyed by tokenId,
 * activity rows by `${block}-${logIndex}`, and the cursor only moves forward.
 */
export async function sync(): Promise<{ fromBlock: string; toBlock: string; logs: number }> {
  const client = publicClient();
  const db = await getDb();
  const cursors = db.collection("cursors");
  const bundles = db.collection<BundleDoc>("bundles");
  const activity = db.collection("activity");

  const cursor = await cursors.findOne({ _id: chain.id as never });
  const head = await client.getBlockNumber();
  let from = cursor ? BigInt(cursor.lastBlock as number) + 1n : BigInt(deployment.deployBlock);
  if (from > head) return { fromBlock: from.toString(), toBlock: head.toString(), logs: 0 };

  let total = 0;
  while (from <= head) {
    const to = from + CHUNK > head ? head : from + CHUNK;
    const logs = await client.getContractEvents({
      address: deployment.stockPack,
      abi: stockPackAbi,
      fromBlock: from,
      toBlock: to,
    });

    for (const log of logs) {
      total += 1;
      const id = `${log.blockNumber}-${log.logIndex}`;
      const args = log.args as Record<string, unknown>;

      if (log.eventName === "Packed") {
        const tokenId = Number(args.tokenId as bigint);
        const block = await client.getBlock({ blockNumber: log.blockNumber });
        await bundles.updateOne(
          { _id: tokenId },
          {
            $set: {
              chainId: chain.id,
              name: args.name as string,
              creator: (args.creator as string).toLowerCase(),
              owner: (args.creator as string).toLowerCase(),
              tokens: (args.tokens as string[]).map((t) => t.toLowerCase()),
              amounts: (args.amounts as bigint[]).map((a) => a.toString()),
              sealedAt: Number(block.timestamp),
              status: "live",
              blockNumber: Number(log.blockNumber),
              txHash: log.transactionHash,
            },
          },
          { upsert: true },
        );
        await activity.updateOne(
          { _id: id as never },
          { $set: { chainId: chain.id, type: "packed", tokenId, actor: (args.creator as string).toLowerCase(), blockNumber: Number(log.blockNumber), txHash: log.transactionHash } },
          { upsert: true },
        );
      } else if (log.eventName === "Transfer") {
        const tokenId = Number(args.tokenId as bigint);
        const toAddr = (args.to as string).toLowerCase();
        const fromAddr = (args.from as string).toLowerCase();
        if (fromAddr !== ZERO && toAddr !== ZERO) {
          await bundles.updateOne({ _id: tokenId }, { $set: { owner: toAddr } });
          await activity.updateOne(
            { _id: id as never },
            { $set: { chainId: chain.id, type: "transfer", tokenId, actor: toAddr, blockNumber: Number(log.blockNumber), txHash: log.transactionHash } },
            { upsert: true },
          );
        }
      } else if (log.eventName === "Unpacked") {
        const tokenId = Number(args.tokenId as bigint);
        await bundles.updateOne({ _id: tokenId }, { $set: { status: "redeemed" } });
        await activity.updateOne(
          { _id: id as never },
          { $set: { chainId: chain.id, type: "unpacked", tokenId, actor: (args.redeemer as string).toLowerCase(), blockNumber: Number(log.blockNumber), txHash: log.transactionHash } },
          { upsert: true },
        );
      } else if (log.eventName === "EmergencyUnpacked") {
        const tokenId = Number(args.tokenId as bigint);
        await bundles.updateOne({ _id: tokenId }, { $set: { status: "emergency" } });
        await activity.updateOne(
          { _id: id as never },
          { $set: { chainId: chain.id, type: "emergency", tokenId, actor: (args.redeemer as string).toLowerCase(), blockNumber: Number(log.blockNumber), txHash: log.transactionHash } },
          { upsert: true },
        );
      } else if (log.eventName === "Claimed") {
        await activity.updateOne(
          { _id: id as never },
          { $set: { chainId: chain.id, type: "claimed", actor: (args.holder as string).toLowerCase(), blockNumber: Number(log.blockNumber), txHash: log.transactionHash } },
          { upsert: true },
        );
      }
    }

    await cursors.updateOne({ _id: chain.id as never }, { $set: { lastBlock: Number(to) } }, { upsert: true });
    from = to + 1n;
  }
  return { fromBlock: "-", toBlock: head.toString(), logs: total };
}

/**
 * Mongo-less fallback: scan the chain directly (fine at demo scale, and the only
 * mode used in local dev without a database).
 */
export async function scanBundles(): Promise<BundleDoc[]> {
  const client = publicClient();
  const head = await client.getBlockNumber();
  const out = new Map<number, BundleDoc>();
  let from = BigInt(deployment.deployBlock);
  while (from <= head) {
    const to = from + CHUNK > head ? head : from + CHUNK;
    const logs = await client.getContractEvents({
      address: deployment.stockPack,
      abi: stockPackAbi,
      fromBlock: from,
      toBlock: to,
    });
    for (const log of logs) {
      const args = log.args as Record<string, unknown>;
      if (log.eventName === "Packed") {
        const tokenId = Number(args.tokenId as bigint);
        out.set(tokenId, {
          _id: tokenId,
          chainId: chain.id,
          name: args.name as string,
          creator: (args.creator as string).toLowerCase(),
          owner: (args.creator as string).toLowerCase(),
          tokens: (args.tokens as string[]).map((t) => t.toLowerCase()),
          amounts: (args.amounts as bigint[]).map((a) => a.toString()),
          sealedAt: 0,
          status: "live",
          blockNumber: Number(log.blockNumber),
          txHash: log.transactionHash,
        });
      } else if (log.eventName === "Transfer") {
        const tokenId = Number(args.tokenId as bigint);
        const doc = out.get(tokenId);
        const toAddr = (args.to as string).toLowerCase();
        const fromAddr = (args.from as string).toLowerCase();
        if (doc && fromAddr !== ZERO) {
          if (toAddr === ZERO) doc.status = doc.status === "live" ? "redeemed" : doc.status;
          else doc.owner = toAddr;
        }
      } else if (log.eventName === "EmergencyUnpacked") {
        const doc = out.get(Number(args.tokenId as bigint));
        if (doc) doc.status = "emergency";
      }
    }
    from = to + 1n;
  }
  return [...out.values()].sort((a, b) => b._id - a._id);
}

export async function queryBundles(opts: {
  owner?: string;
  status?: string;
  id?: number;
  limit: number;
}): Promise<BundleDoc[]> {
  if (!mongoEnabled()) {
    let all = await scanBundles();
    if (opts.id !== undefined) all = all.filter((b) => b._id === opts.id);
    if (opts.owner) all = all.filter((b) => b.owner === opts.owner!.toLowerCase() && b.status === "live");
    if (opts.status) all = all.filter((b) => b.status === opts.status);
    return all.slice(0, opts.limit);
  }
  await sync(); // cheap incremental catch-up on read paths too
  const db = await getDb();
  // docs are keyed by tokenId; the chain filter keeps a leftover testnet doc from
  // masquerading as a mainnet bundle when the same DB is reused across networks
  const q: Record<string, unknown> = { chainId: chain.id };
  if (opts.id !== undefined) q._id = opts.id;
  if (opts.owner) {
    q.owner = opts.owner.toLowerCase();
    q.status = "live";
  }
  if (opts.status) q.status = opts.status;
  return db
    .collection<BundleDoc>("bundles")
    .find(q as never)
    .sort({ _id: -1 })
    .limit(opts.limit)
    .toArray();
}
