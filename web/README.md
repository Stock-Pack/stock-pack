# StockPack Web

Next.js (App Router) dApp for the StockPack escrow. wagmi v3 + viem (built-in `robinhood` chain definitions) + RainbowKit; MongoDB as the event-indexed query layer — **the chain is always the source of truth** (bundle pages re-verify via `getBasket`).

## Run locally (against anvil)

```bash
# 1. chain + contracts (repo root)
anvil &
forge script script/Deploy.s.sol      --rpc-url http://127.0.0.1:8545 --private-key <anvil key> --broadcast
forge script script/DeployMocks.s.sol --rpc-url http://127.0.0.1:8545 --private-key <anvil key> --broadcast
cp deployments/31337*.json web/lib/deployments/

# 2. app
cd web
cp .env.example .env.local          # NEXT_PUBLIC_CHAIN=local
npm run dev
```

Import an anvil private key into MetaMask (network http://127.0.0.1:8545, chain 31337) and use the per-token faucet buttons on /create.

## Testnet / mainnet

1. Deploy contracts to 46630 / 4663, then copy `deployments/<chainId>*.json` into `web/lib/deployments/`.
2. Set `NEXT_PUBLIC_CHAIN=testnet|mainnet`, a WalletConnect projectId, an Alchemy RPC, and `MONGODB_URI`.
3. `vercel.json` schedules `/api/sync` every 5 minutes (set `CRON_SECRET`); the app also triggers a sync after each user transaction.

## Structure

- `lib/contracts.ts` — network/deployment/RPC resolution (`NEXT_PUBLIC_CHAIN`)
- `lib/tokenlist.ts` — canonical token allowlist; real Stock Tokens behind `NEXT_PUBLIC_ENABLE_REAL_TOKENS` (legal gate)
- `lib/indexer.ts` — chunked `getContractEvents` → MongoDB (`bundles`/`activity`/`cursors`); chain-scan fallback without Mongo
- `app/create` — token picker + faucets, amounts, 31-byte name, **on-chain `previewSVG` live preview**, sequential approval checklist, mint
- `app/bundle/[tokenId]` — real tokenURI card, basket table with ERC-8056 share-equivalents, simulate-first redeem with emergency escape hatch, OpenSea link/refresh
- `app/my` — owned bundles + pending emergency claims
- `app/api/og/[tokenId]` — 1200×630 PNG unfurl; `app/api/refresh/[tokenId]` — OpenSea refresh proxy (server key, throttled)
