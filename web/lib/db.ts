import { MongoClient, type Db } from "mongodb";

/**
 * Cached MongoDB client (survives dev hot-reload and warm lambda reuse).
 * MongoDB is a QUERY INDEX only — the chain is always the source of truth.
 * When MONGODB_URI is unset, callers fall back to direct chain scans.
 */
const globalForMongo = globalThis as unknown as { _mongoClient?: MongoClient };

export function mongoEnabled(): boolean {
  return Boolean(process.env.MONGODB_URI);
}

export async function getDb(): Promise<Db> {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not set");
  if (!globalForMongo._mongoClient) {
    globalForMongo._mongoClient = new MongoClient(uri);
  }
  const client = globalForMongo._mongoClient;
  await client.connect();
  return client.db(process.env.MONGODB_DB ?? "stockpack");
}

export type BundleDoc = {
  _id: number; // tokenId
  chainId: number;
  name: string;
  creator: string;
  owner: string;
  tokens: string[];
  amounts: string[]; // raw units as decimal strings (bigint-safe)
  sealedAt: number; // unix seconds
  status: "live" | "redeemed" | "emergency";
  blockNumber: number;
  txHash: string;
};

export type ActivityDoc = {
  _id: string; // `${blockNumber}-${logIndex}` — idempotent upserts
  chainId: number;
  type: "packed" | "unpacked" | "emergency" | "claimed" | "transfer";
  tokenId?: number;
  actor: string;
  blockNumber: number;
  txHash: string;
};

export type CursorDoc = {
  _id: number; // chainId
  lastBlock: number;
};
