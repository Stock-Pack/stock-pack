# StockPack — Technical Architecture (internal / AI-agent reference)

> Audience: developers and AI coding agents working on this repo. This document explains how the
> whole system works end to end — contracts, deploy scripts, tests, the Next.js dApp, the indexer,
> hosting, and the security model — with the load-bearing code inline. It intentionally contains
> **no secrets** (no private keys, DB credentials, or cron secrets); those live only in gitignored
> `.env` files and Vercel project settings. For public/marketing copy see `docs/PRODUCT.md`.
>
> Last verified against the codebase: 2026-09-02.

---

## 0. One-paragraph summary

StockPack is an **ownerless ERC-721 basket-wrapper escrow** on **Robinhood Chain** (Arbitrum Orbit L2;
mainnet chain id `4663`, testnet `46630`). A user deposits a basket of ERC-20s (tokenized stocks such
as NVDA/AAPL, or coins such as WETH/USDG) and receives one NFT "portfolio card" that is a bearer
claim on *exactly* those balances. Whoever holds the card can burn it at any time to withdraw every
underlying token in a single transaction. There are no oracles, no fees, no upgrade path, and no
admin that can touch funds. Metadata (JSON + SVG art) is generated 100% on-chain by a separate,
view-only renderer contract. A Next.js dApp provides the UI, with MongoDB as an optional
event-indexed cache; the chain is always the source of truth.

---

## 1. Repository map

```
StockPack/
├── src/
│   ├── StockPack.sol                # the escrow (ERC-721 core + pack/unpack/emergency/claim)
│   ├── StockPackRenderer.sol        # on-chain tokenURI/contractURI/previewSVG (view-only)
│   ├── libraries/SVGCard.sol        # SVG assembly, amount/date formatting, XML escaping
│   ├── interfaces/
│   │   ├── IStockPack.sol           # external surface + custom errors + events
│   │   ├── IStockPackRenderer.sol
│   │   └── external/ISignatureTransfer.sol   # Permit2 SignatureTransfer subset
│   └── mocks/MockStockToken.sol     # demo ERC-20 with faucet() + ERC-8056 uiMultiplier surface
├── script/
│   ├── Deploy.s.sol                 # renderer + escrow bootstrap (address prediction), writes deployments/<chainId>.json
│   ├── DeployMocks.s.sol            # 8 mock tokens + 4 showcase bundles, writes deployments/<chainId>.mocks.json
│   ├── AddMockCoins.s.sol           # append-only: adds mWETH/mUSDG to an already-deployed demo
│   └── SmokeTest.s.sol              # live pack/unpack/tokenURI/emergency/claim check after deploy
├── test/
│   ├── utils/TestBase.sol           # shared fixture (production bootstrap reproduced)
│   ├── mocks/WeirdTokens.sol        # adversarial ERC-20 zoo
│   ├── unit/{StockPack,Renderer,WeirdTokens}.t.sol
│   ├── fuzz/PackUnpackFuzz.t.sol
│   ├── invariant/{Handler.sol,StockPackInvariants.t.sol}
│   ├── fork/RobinhoodForkTest.t.sol # against live mainnet (skips off-fork)
│   └── fixtures/permit2.bytecode.txt
├── deployments/                     # <chainId>.json + <chainId>.mocks.json written by scripts
├── web/                             # Next.js 16 App Router dApp (see §6)
│   ├── app/                         # routes + API handlers
│   ├── components/                  # ApprovalChecklist, BuyPanel, LiveCardPreview, BundleCard, …
│   ├── lib/                         # contracts.ts, indexer.ts, db.ts, tokenlist.ts, discovery.ts, uniswap.ts, display.ts, wagmi.ts, abi/, deployments/
│   ├── next.config.ts               # CSP + security headers
│   └── vercel.json                  # cron: GET /api/sync every 5 min
├── foundry.toml, remappings.txt, VERSIONS.md, README.md
└── .github/workflows/ci.yml         # fmt, build --sizes, unit+invariant tests, fork tests, slither
```

Toolchain (pinned, see `VERSIONS.md`): Foundry **1.8.1**, solc **0.8.36**, OpenZeppelin **v5.7.0**,
forge-std **v1.16.2**, EVM target **cancun** (EIP-1153 transient storage verified live on chain 46630,
which is what makes `ReentrancyGuardTransient` safe).

`foundry.toml` essentials: `via_ir = true`, `optimizer_runs = 200` (default) / `10000` (`[profile.production]`),
invariants run with `fail_on_revert = true`, `fs_permissions` = read `./test/fixtures`, read-write `./deployments`.

---

## 2. Core contract: `src/StockPack.sol`

`contract StockPack is ERC721, ReentrancyGuardTransient, IStockPack`

### 2.1 Storage

```solidity
struct Basket  { address[] tokens; uint256[] amounts; } // tokens strictly ascending; amounts = raw units measured as received deltas
struct BundleMeta { address creator; uint64 sealedAt; } // block.timestamp — never block.number on Nitro

uint256 public constant MAX_BASKET_SIZE = 16;
uint256 public constant MAX_NAME_BYTES  = 31;            // single-slot short string
ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

mapping(uint256 => Basket)      private _baskets;
mapping(uint256 => BundleMeta)  private _meta;
mapping(uint256 => string)      private _names;
mapping(address holder => mapping(address token => uint256)) private _claimable; // only emergencyUnpack writes; claim() drains
mapping(address token => uint256) public totalEscrowed;   // PUBLIC solvency ledger: balanceOf(this) >= totalEscrowed[token], always

uint256 private _nextTokenId = 1;                         // monotonic; burned ids never reused
address public renderer;                                  // the ONLY mutable admin pointer (view-only contract)
address public immutable artist;                          // may swap renderer until locked
bool    public rendererLocked;
```

Design rules encoded here:
- **Accounting is in raw token units** and never reads live `balanceOf` for state. Donations, airdrops,
  and rebase noise cannot change what a card redeems for.
- **`totalEscrowed` is the public liability ledger.** Anyone can check solvency on-chain for every token.
- **Ids are monotonic** so a stale marketplace listing/approval can never attach to a future basket.

### 2.2 Packing (deposit → mint)

```solidity
function pack(string calldata name, address[] calldata tokens, uint256[] calldata amounts)
    external nonReentrant returns (uint256 tokenId)
{
    uint256 n = tokens.length;
    if (n != amounts.length) revert LengthMismatch();
    _checkShape(n, bytes(name).length);            // 1..16 tokens, 1..31-byte name

    address prev;
    for (uint256 i; i < n; ++i) {
        address token = tokens[i]; uint256 amount = amounts[i];
        _checkEntry(token, amount, prev);          // token > prev (sorted+unique+non-zero), amount != 0, token != this
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (IERC20(token).balanceOf(address(this)) - before != amount) revert FeeOnTransferRejected(token);
        prev = token;
    }
    tokenId = _mintBasket(name, tokens, amounts);
}
```

- **Strict ascending order** (`token > prev`, `prev` starts at `address(0)`) enforces uniqueness,
  canonical order, and rejects `address(0)` in one comparison. The frontend sorts before calling.
- **Fee-on-transfer rejection** via balance-delta strict equality guarantees "1:1 backed" is literally
  true for everything admitted. Rebasing-raw-balance tokens are *unsupported* (Robinhood Stock Tokens
  do not rebase; ERC-8056 `uiMultiplier` handles splits/dividends off the raw balance).

```solidity
function _mintBasket(string calldata name, address[] memory tokens, uint256[] memory amounts) private returns (uint256 tokenId) {
    tokenId = _nextTokenId++;
    Basket storage b = _baskets[tokenId];
    b.tokens = tokens; b.amounts = amounts;
    _meta[tokenId]  = BundleMeta({creator: msg.sender, sealedAt: uint64(block.timestamp)});
    _names[tokenId] = name;
    for (uint256 i; i < tokens.length; ++i) totalEscrowed[tokens[i]] += amounts[i];
    emit Packed(tokenId, msg.sender, name, tokens, amounts);
    _mint(msg.sender, tokenId);   // _mint, NOT _safeMint: no receiver callback may take control mid-mint
}
```

- All storage effects and the `Packed` event land **before** `_mint`.
- `_mint` (not `_safeMint`) is deliberate (Solv double-mint lesson). Consequence: a *contract* that calls
  `pack()` must itself be able to call `transferFrom`/`unpackTo`, or the funds are unrecoverable
  (`test_mintToNaiveContract_stuckByDesign` documents this).

**Permit2 path** — `packWithPermit2(name, PermitBatchTransferFrom permit, bytes signature)`: basket
contents derive *solely* from `permit.permitted[]` (declaration and funding cannot diverge), uses
Permit2 **SignatureTransfer** (one-time, no standing allowance), and applies the same sorted/fee-delta
checks after `PERMIT2.permitTransferFrom(...)`. The dApp currently uses the plain `pack()` +
per-token `approve` flow; Permit2 is available for integrators.

### 2.3 Redemption (burn → withdraw)

```solidity
function unpack(uint256 tokenId) external { unpackTo(tokenId, msg.sender); }

function unpackTo(uint256 tokenId, address recipient) public nonReentrant {
    if (recipient == address(0)) revert ZeroRecipient();
    if (ownerOf(tokenId) != msg.sender) revert NotBasketOwner();   // approvals/operators NEVER honored

    (address[] memory tokens, uint256[] memory amounts) = _closeBasket(tokenId); // copy, delete all rows, _burn
    for (uint256 i; i < tokens.length; ++i) totalEscrowed[tokens[i]] -= amounts[i];
    emit Unpacked(tokenId, msg.sender, recipient);

    for (uint256 i; i < tokens.length; ++i) IERC20(tokens[i]).safeTransfer(recipient, amounts[i]); // interactions last
}
```

- **Strictly `ownerOf`-only.** ERC-721 `approve`/`setApprovalForAll` are deliberately not honored on
  any burn path — a standing marketplace operator approval can never destroy a basket (NFT Trader /
  Gondi lesson). Marketplaces need transfers, never redemption.
- `unpackTo(recipient)` lets a blocklisted holder redeem to a clean address.
- Strict CEI: storage is deleted and the NFT burned before any external transfer; a token hook
  re-entering finds the id already dead.

### 2.4 Emergency path (frozen constituent)

```solidity
function emergencyUnpack(uint256 tokenId) external nonReentrant {
    if (ownerOf(tokenId) != msg.sender) revert NotBasketOwner();
    (address[] memory tokens, uint256[] memory amounts) = _closeBasket(tokenId);
    for (uint256 i; i < tokens.length; ++i) _claimable[msg.sender][tokens[i]] += amounts[i];
    emit EmergencyUnpacked(tokenId, msg.sender, tokens, amounts);
}   // ZERO external calls: a paused/blocklisting token structurally cannot make this revert

function claim(address token, address recipient) external nonReentrant {
    if (recipient == address(0)) revert ZeroRecipient();
    uint256 owed = _claimable[msg.sender][token];
    if (owed == 0) revert NothingToClaim();
    uint256 bal = IERC20(token).balanceOf(address(this));
    uint256 pay = owed <= bal ? owed : bal;           // best-effort under shortfall, remainder stays claimable
    if (pay == 0) revert NothingToClaim();
    _claimable[msg.sender][token] = owed - pay;
    totalEscrowed[token] -= pay;
    emit Claimed(msg.sender, token, recipient, pay);
    IERC20(token).safeTransfer(recipient, pay);
}
```

Why two paths: Robinhood Stock Tokens are pausable, upgradeable beacon proxies. If the issuer pauses
one constituent, atomic `unpack` would revert forever. `emergencyUnpack` burns the card and converts
each leg into a per-token **pull claim**; the healthy legs are claimable immediately, the frozen leg
whenever it thaws. `claim` pays `min(owed, pool)` so a misbehaving token can never brick claims;
under a real shortfall (e.g. a downward-rebasing token) it is first-come-first-served, and there is
**no admin rescue** by design. The ledger identity is `totalEscrowed == live baskets + unclaimed emergency rows`.

### 2.5 The only admin surface

```solidity
function setRenderer(address newRenderer) external {   // artist only, until locked, must be a contract
    if (msg.sender != artist) revert NotArtist();
    if (rendererLocked) revert RendererIsLocked();
    if (newRenderer.code.length == 0) revert RendererNotContract();
    renderer = newRenderer; emit RendererChanged(newRenderer);
}
function lockRenderer() external { if (msg.sender != artist) revert NotArtist(); rendererLocked = true; emit RendererLocked(); }
```

The renderer is a pure view surface (`tokenURI`, `contractURI`, `previewSVG`) — it cannot reach escrow
storage or move tokens. Policy: lock within 14 days of mainnet deploy, ideally with a hardware-wallet
`artist` key (`ARTIST_ADDRESS` env at deploy).

### 2.6 Views, events, errors

Views: `getBasket(id) → (tokens[], amounts[])`, `bundleMeta(id) → (name, creator, sealedAt)`,
`claimable(holder, token)`, `totalEscrowed(token)`, `totalMinted()`, `tokenURI(id)`, `contractURI()`,
`renderer()`, `artist()`, `rendererLocked()`. `getBasket`/`bundleMeta` revert `NonexistentToken` for
burned ids (no residual state — `INV_NO_RESIDUAL`).

Events: `Packed(tokenId, creator, name, tokens, amounts)`, `Unpacked(tokenId, redeemer, recipient)`,
`EmergencyUnpacked(tokenId, redeemer, tokens, amounts)`, `Claimed(holder, token, recipient, amount)`,
`RendererChanged(renderer)`, `RendererLocked()` + standard ERC-721 `Transfer`/`Approval`/`ApprovalForAll`.

Errors: `LengthMismatch, EmptyBasket, BasketTooLarge, TokensNotSortedUnique, ZeroAmount, SelfToken,
NameLength, FeeOnTransferRejected(token), NotBasketOwner, NothingToClaim, ZeroRecipient,
NonexistentToken, RendererIsLocked, NotArtist, RendererNotContract`.

---

## 3. Renderer: `src/StockPackRenderer.sol` + `src/libraries/SVGCard.sol`

Separate descriptor contract (Uniswap V3 pattern) so string-building bytecode never pushes the escrow
toward the EIP-170 size limit. Bound to the escrow at construction via a **precomputed address**
(the deploy script computes the escrow's future CREATE address, deploys the renderer with it, then
deploys the escrow and asserts equality).

### 3.1 `tokenURI` pipeline

```
getBasket + bundleMeta
  → _sanitize(name, 31)                       # printable ASCII 0x20–0x7E only, '<' and '>' dropped, truncated
  → _display(tokens, amounts)                 # per token: _tokenSymbol (raw staticcall, validated) + SVGCard.formatAmount(amount, _tokenDecimals)
  → SVGCard.render(CardData{...hue: _hue(name, creator)})   # 350×500 SVG, ≤ 8 rows + "+N more", XML-escaped
  → _wrapJSON: name, description, external_url, image (base64 SVG), attributes
  → "data:application/json;base64,…"
```

Hardening specifics:
- `symbol()` / `decimals()` are read with **raw `staticcall` + manual return-data validation** (no
  `abi.decode` bombs). Handles bytes32-style symbols (MKR), malformed offsets, 10 KB symbols, reverts —
  all degrade to a short-hex fallback (`0x1234ab`) instead of bricking `tokenURI`. Symbols are capped
  at 11 chars. `decimals()` is display-only; values > 77 clamp to 18.
- Every attacker-controlled string is sanitized → JSON-escaped (`Strings.escapeJSON`) → XML-escaped
  (`SVGCard.escapeXML`) at the layer it lands in. Tested with `<script>` and `<img onerror>` payloads.
- Accent hue is `keccak256(name, creator) % 360` — **tokenId-independent** so the pre-mint preview
  (`previewSVG`) matches the minted card exactly (`test_previewSVG_parity_tokenIdIndependentLayers`).

### 3.2 Metadata content (current renderer, testnet `0x0dB0…5969`)

```solidity
string memory bundleUrl = string.concat(baseUrl, "/bundle/", idStr);   // baseUrl: storage, seeded "https://stock-pack.vercel.app"
string memory description = string.concat(
    "Worth exactly ", _contents(syms, amts),          // e.g. "12 mAMZN + 0.1 mMSFT + 13 mNVDA"
    " - a bearer claim redeemable 1:1. As the NFT holder you can burn this card via unpack() to withdraw those exact tokens to your wallet in one transaction (one-click Unpack at ",
    bundleUrl,
    "); redemption is owner-only, so marketplace approvals can never drain it. Amounts are raw token units, fixed at mint - verify on-chain with getBasket(",
    idStr,
    "). Tokenized stocks may accrue corporate-action value via their ERC-8056 uiMultiplier while escrowed. App: ", baseUrl
);
// JSON: {"name":"<name> · StockPack #<id>","description":…,"external_url":<bundleUrl>,"image":"data:image/svg+xml;base64,…","attributes":[...]}
```

Attributes: `Stocks` (count), `Bundle Name`, `Sealed` (YYYY-MM-DD), then one `{trait_type: <symbol>, value: <amount>}`
per constituent — this is what gives per-symbol filters on marketplaces.

> `baseUrl` is renderer **storage**, not a constant: `setBaseUrl(string)` — gated to the escrow's
> `artist` via `stockPack.artist()` — re-points every existing and future card at a new domain in
> one tx, and keeps working **after** `lockRenderer()` (that only freezes the renderer pointer).
> The setter validates `https://` prefix, no trailing slash, printable ASCII, no `"` `\` `<` `>`,
> ≤ 200 bytes, so the string can be spliced verbatim into the JSON. It is the renderer's only
> mutable state and is display-only; the deploy script seeds it from the `BASE_URL` env
> (default `https://stock-pack.vercel.app`) and records it in `deployments/<chainid>.json`.

### 3.3 `SVGCard.formatAmount` (mirrored in `web/lib/display.ts`)

- ≥ 0.01 units: up to 2 truncated decimals, trailing zeros trimmed (`1`, `1.5`, `1.23`).
- 0 < amount < 0.01: up to 6 truncated decimals, trimmed (`0.005`, `0.000123`).
- below 10⁻⁶ units: `"<0.000001"` — never a lying `0.00`.
- Overflow-safe for 76–77-decimal tokens (`(amount % unit) / (unit / 100)` instead of `* 100`).
- Pinned by 17 exact assertions in `test_formatAmount_dustHonesty`.

`formatDate` = Howard Hinnant's days-from-civil inverse (unix → `YYYY-MM-DD`). Size budget test:
worst case (16 tokens, long symbols, 31-char name) `tokenURI < 8192` bytes, raw SVG `< 4096`.

---

## 4. Deploy scripts (`script/`)

### `Deploy.s.sol` — bootstrap with address prediction

```solidity
address predicted = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
StockPackRenderer renderer = new StockPackRenderer(predicted);
StockPack pack = new StockPack(address(renderer), artist);          // artist = vm.envOr("ARTIST_ADDRESS", deployer)
vm.stopBroadcast();
require(address(pack) == predicted, "bootstrap: address prediction failed");
require(address(renderer.stockPack()) == address(pack), "bootstrap: renderer not bound");
require(bytes(IStockPackRenderer(address(renderer)).contractURI()).length > 0, "contractURI dead");
```

Writes `deployments/<chainId>.json` = `{stockPack, renderer, artist, chainId, deployBlock}`.
**`deployBlock` uses ArbSys** because on Nitro chains `block.number` is the approximate *L1* block
(~100M behind the L2 height); recording the wrong one once made the indexer sweep 100M empty blocks:

```solidity
function _l2BlockNumber() private view returns (uint256) {
    (bool ok, bytes memory d) = address(0x64).staticcall(abi.encodeWithSignature("arbBlockNumber()"));
    return ok && d.length == 32 ? abi.decode(d, (uint256)) : block.number;   // anvil fallback
}
```

### `DeployMocks.s.sol`, `AddMockCoins.s.sol`, `SmokeTest.s.sol`

- `DeployMocks`: 8 `MockStockToken`s (mNVDA, mAAPL, mMSFT, mTSLA, mAMZN, mGOOG, mWETH, mUSDG; all 18 dec;
  public `faucet()` with cooldown; ERC-8056 `uiMultiplier`/`balanceOfUI` surface) + 4 showcase bundles.
  Writes `deployments/<chainId>.mocks.json` (`symbol → address`, plus `chainId`).
- `AddMockCoins`: append-only upgrade for a demo deployed before coins existed (writes `$.mWETH`, `$.mUSDG`
  into the existing mocks JSON, seeds one mixed bundle).
- `SmokeTest`: pack → ownerOf → tokenURI → unpack, then pack → emergencyUnpack → claim×2, live on the target chain.

Typical commands (keystore-based; never a plaintext key):

```bash
forge script script/Deploy.s.sol      --rpc-url robinhood_testnet --account stockpack-testnet-deployer --broadcast
forge script script/DeployMocks.s.sol --rpc-url robinhood_testnet --account stockpack-testnet-deployer --broadcast
forge script script/SmokeTest.s.sol   --rpc-url robinhood_testnet --account stockpack-testnet-deployer --broadcast
# copy deployments/<chainId>*.json → web/lib/deployments/ after every deploy
# verify: --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api/  (Etherscan does not support 4663/46630)
```

Renderer upgrade (until locked): deploy new `StockPackRenderer(<escrow>)`, then `cast send <escrow> "setRenderer(address)" <new>` from the artist key; update both `46630.json` files.

---

## 5. Test suite (`test/`) — what is proven

`forge test` runs 49 unit/fuzz/renderer/adversarial tests + invariants. CI (`.github/workflows/ci.yml`,
`FOUNDRY_PROFILE=ci`: 1000 fuzz runs, 512×50 invariants) also runs `forge fmt --check`, `forge build --sizes`
(EIP-170 gate), fork tests against mainnet (continue-on-error, public RPC), and Slither (`fail-on: high`).

| File | Proves |
|---|---|
| `unit/StockPack.t.sol` (26) | every revert path; approvals/operators can't burn; `unpackTo` for blocklisted holders; emergency + additive claims; Permit2 happy/unsorted (real Permit2 bytecode `vm.etch`ed from fixture); renderer one-way lock; naive-contract footgun |
| `unit/Renderer.t.sol` | valid JSON + traits; size budget; hostile symbols/names never break metadata or inject `<script>`; preview/minted hue parity; `formatAmount` ladder; `formatDate`; `contractURI` |
| `unit/WeirdTokens.t.sol` | downward-rebase contagion has *defined* best-effort behavior; upward rebase never skews; pause never bricks other legs; reentrant token can't double-mint/double-claim; revert-on-zero round-trips; donations never skew ledger |
| `fuzz/PackUnpackFuzz.t.sol` | `FUZZ_ROUND_TRIP` exact conservation (1–16 tokens, any amounts); `FUZZ_AUTH` only owner burns; `FUZZ_NAME_NEVER_BREAKS_METADATA` (arbitrary 1–31 bytes); emergency-claim conservation |
| `invariant/StockPackInvariants.t.sol` | `INV_SOLVENCY` (`bal == totalEscrowed + donations`), `INV_LEDGER` (`totalEscrowed == live + unclaimed`), `INV_SUPPLY`, `INV_MONOTONIC_IDS`, `INV_NO_RESIDUAL`, and `INV_REDEMPTION_FLOOR` in `afterInvariant()` — every live basket is actually unpacked and must pay exactly its recorded amounts |
| `fork/RobinhoodForkTest.t.sol` | Permit2/Multicall3/Seaport 1.6 predeployed; real AAPL/NVDA expose `symbol/decimals/uiMultiplier`; real AAPL round-trips through the escrow (pack → transfer → unpack by buyer) |

The invariant `Handler` uses a 4-token universe (two 18-dec, one 6-dec, one `BlocklistToken` that can
freeze the escrow itself) with ghost ledgers (`ghostLive`, `ghostClaims`, `ghostDonated`) and
non-vacuity call counters.

---

## 6. Web app (`web/`) — Next.js 16 App Router

Stack: `next 16.3.4`, `react 19.2`, `wagmi 3.7`, `viem 2.56`, `@rainbow-me/rainbowkit 2.2`,
`@tanstack/react-query 5`, `mongodb 7.6`, Tailwind v4, `next/og`. `web/.npmrc` has
`legacy-peer-deps=true` (RainbowKit 2 declares a wagmi 2 peer; the app uses wagmi 3 — required for Vercel installs).

### 6.1 Configuration is one build-time switch

```ts
// web/lib/contracts.ts
const NETWORK = (process.env.NEXT_PUBLIC_CHAIN ?? "local") as "local" | "testnet" | "mainnet";
const CHAINS      = { local: foundry, testnet: robinhoodTestnet, mainnet: robinhood };   // viem built-in chain defs
const DEPLOYMENTS = { local: d31337,  testnet: d46630,          mainnet: d4663 };        // static JSON imports
export const deployment = { ...DEPLOYMENTS[NETWORK], stockPack: process.env.NEXT_PUBLIC_STOCKPACK_ADDRESS ?? DEPLOYMENTS[NETWORK].stockPack };
export const serverRpcUrl = process.env.RPC_URL ?? process.env.NEXT_PUBLIC_RPC_URL ?? chain.rpcUrls.default.http[0];
export const clientRpcUrl = process.env.NEXT_PUBLIC_RPC_URL ?? chain.rpcUrls.default.http[0];
export const isDeployed   = deployment.stockPack !== ZERO;
export const mockTokens   = Object.entries(MOCKS[NETWORK]).filter(([k, v]) => k !== "chainId" && typeof v === "string" && v.startsWith("0x")).map(...);
export function openSeaAssetUrl(id) { return NETWORK === "mainnet" ? `https://opensea.io/assets/robinhood/${deployment.stockPack}/${id}` : null; }
```

Everything downstream — wagmi transports, addresses, token gating, OpenSea links, refresh route,
CSP localhost allowance, header label — derives from `NEXT_PUBLIC_CHAIN`. Switching networks = rebuild.

Environment variables (`web/.env.example`):

| Var | Scope | Purpose |
|---|---|---|
| `NEXT_PUBLIC_CHAIN` | client | `local` / `testnet` / `mainnet` |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | client | optional; injected wallets work without it |
| `NEXT_PUBLIC_RPC_URL` / `RPC_URL` | client / server | RPC overrides (server one used by indexer + OG route) |
| `NEXT_PUBLIC_STOCKPACK_ADDRESS` | client | override for the deployments JSON |
| `MONGODB_URI`, `MONGODB_DB` | server | enable the Mongo index; unset ⇒ chain-scan fallback |
| `CRON_SECRET` | server | **required**; `/api/sync` returns 503 without it |
| `OPENSEA_API_KEY` | server | metadata refresh proxy (mainnet only) |
| `NEXT_PUBLIC_ENABLE_REAL_TOKENS` | client | `"true"` shows real Robinhood Stock Tokens; anything else hides them (fails closed) |

### 6.2 Token allowlist + legal gate — `web/lib/tokenlist.ts`

```ts
const realStocksEnabled = process.env.NEXT_PUBLIC_ENABLE_REAL_TOKENS === "true";
if (network === "mainnet") {
  const coins  = REAL_MAINNET_COINS.map(...);                       // USDG (6 dec), WETH (18 dec) — not securities, ungated
  const stocks = realStocksEnabled ? REAL_MAINNET_STOCKS.map(...) : [];   // 9 canonical Robinhood Stock Tokens
  return [...stocks, ...coins, ...mocks];
}
return mocks;                                                        // local + testnet: mock tokens only
```

`ListedToken = { symbol, address, decimals, verified, real, category: "stock"|"coin"|"other", hasFaucet }`
(`"other"` = a token the user added by address on `/create`; always `verified: false`).
The contract cannot know whether a token called "NVDA" is real; this list is the off-chain answer.
Anything not listed renders with `⚠` (gallery) / `UNVERIFIED — check the address` (detail page);
real tokens get a red `REAL` badge on `/create`.

**Testnet** additionally lists the five official Robinhood testnet Stock Tokens the Robinhood
faucet hands out (TSLA, AMD, AMZN, NFLX, PLTR — `REAL_TESTNET_STOCKS`, all BeaconProxies from
creator `0x2DD5…e5Da`), flagged `verified: true, real: false, faucetUrl: ROBINHOOD_TESTNET_FAUCET`.
They are play tokens, so no legal gate and no `REAL` badge; the fixed addresses matter because
the testnet explorer lists dozens of counterfeit "PLTR"/"AMZN" tokens.

> There is **no geofence** (no middleware/IP check) — counsel recommended one; the owner decided
> on 2026-09-02 to ship without it. The build flag is the only gate on real tokens.

### 6.2a Token discovery — `web/lib/discovery.ts` + `app/api/assets/route.ts`

The curated list is only the seed. On `/create` the catalog is
`mergeTokens(listedTokens(), registryTokens, extraTokens, walletTokens)` — first occurrence wins,
so trust order is curated → registry → user-added → explorer.

| source | when | what it yields |
|---|---|---|
| `GET /api/assets` (server proxy of `https://api.robinhood.com/rhj/assets`, `revalidate: 300`) | mainnet **and** `NEXT_PUBLIC_ENABLE_REAL_TOKENS=true` (`registryEnabled`), else `{tokens: []}` | all ~194 active Robinhood Stock Tokens on chain 4663: `verified: true, real: true, category: "stock"`, logo from `cdn.robinhood.com` only. Proxied because the upstream sends no CORS headers. Verified 2026-09-02 that the 9 hand-typed `REAL_MAINNET_STOCKS` match it exactly. |
| Blockscout `GET {explorer}/api/v2/addresses/{addr}/tokens?type=ERC-20` (client-side, paged ≤5) | any connected wallet, testnet/mainnet | every ERC-20 the wallet holds with balance > 0, as `verified: false, category: "other"` unless a higher-trust source already knows the address. Testnet explorer answers with `access-control-allow-origin: *`; mainnet Blockscout is Cloudflare-challenged so this usually fails there (silently — `catch(() => [])`) and the registry carries mainnet. |

Balances for the merged catalog come from one `useReadContracts` (`balanceOf` × N, Multicall3 is
deployed on both chains at `0xca11…ca11`), polled every 5 s. Only tokens with balance > 0 are
selectable — the picker is wallet-first by design.

### 6.2b Buying tokens — `web/lib/uniswap.ts` + `components/BuyPanel.tsx`

The create page is **wallet-first**: only tokens the wallet actually holds are selectable for
bundling. `BuyPanel` is how a user fills the wallet without leaving the page. Two backends, one UI
(search → "Buy" → how many → confirm):

| network | what "Confirm" does | cap |
|---|---|---|
| local / testnet | `MockStockToken.mint(to, qty)` — free, single tx | `MAX_MINT = 1_000e18` per order (UI mirrors it as `MOCK_MAX_PER_ORDER`) |
| mainnet | Uniswap V3 **exact-output** swap paid in USDG or WETH | pay-token balance ≥ `amountInMax` |

`acquisition(t)` decides the button per row: `"mint"` (`hasFaucet`, mocks) → **Get**; `"swap"`
(`swapEnabled && real`, mainnet) → **Buy**; `"faucet"` (`faucetUrl`, Robinhood testnet stocks) →
**Get free ↗** link to Robinhood's faucet; `"none"` (user-added / explorer-discovered `"other"`)
→ "in wallet — pick it above" or "not sold here". With an empty query the list shows only
acquirable tokens; with a query it searches the whole catalog by ticker, company name, or address
prefix. Nothing in this path touches the escrow.

```ts
// lib/uniswap.ts — official Uniswap deployments for chain 4663, verified on-chain 2026-09-02
UNISWAP.mainnet = { quoterV2: "0x33e885ed0ec9bf04ecfb19341582aadcb4c8a9e7", swapRouter02: "0xcaf681a66d020601342297493863e78c959e5cb2" };
FEE_TIERS = [500, 3000, 10000, 100]; SLIPPAGE_BPS = 50n;
quoteExactOutput(client, tokenIn, tokenOut, amountOut) // simulateContract QuoterV2.quoteExactOutputSingle per tier
  // → lowest amountIn wins; null if no tier quotes; amountInMax = amountIn * 1.005
```

Mainnet confirm sequence in `BuyPanel.confirm()`: balance check → `allowance(user, swapRouter02)`
→ exact-amount `approve` only if short → `SwapRouter02.exactOutputSingle({ tokenIn, tokenOut, fee,
recipient: user, amountOut: qty, amountInMaximum: amountInMax, sqrtPriceLimitX96: 0 })` (no
`deadline` field on Router02) → `waitForTransactionReceipt` → `onBought()` refetches balances.
Quotes live in a `useQuery` keyed on `[pay, token, qty]` with 10 s `staleTime`/`refetchInterval`
(not a `useEffect` — Next 16's `react-hooks/set-state-in-effect` rule rejects that pattern).
There is no Uniswap deployment on testnet, so `swapEnabled` is false there and only mocks appear.

### 6.3 Pages

- **`/` (`app/page.tsx`, server, `force-dynamic`)** — `queryBundles({ limit: 12 })` → `<BundleCard>` grid.
  Errors are never surfaced raw (RPC/Mongo messages can embed URLs with credentials).
- **`/create` (`app/create/page.tsx`, client)** — 4 steps:
  1. *Pick from your wallet* — `useReadContracts(balanceOf × tokens, refetch 5 s)` → `balances: Map<lowercase addr, bigint>`;
     `held` = tokens with balance > 0, sorted by human value desc, rendered as selectable tiles
     (`REAL` / `UNVERIFIED` badges). Empty wallet shows a dashed prompt. Below it: `<BuyPanel>`
     (§6.2b) and `<AddByAddress>` (validates `isAddress`, reads `symbol`/`decimals`, appends a
     `category: "other"` token to local state — merged with `listedTokens()` by address).
  2. *Amounts* — per-token input with a **max** button (`fullUnits(balance)`), dust warning when
     `formatAmount(v) === "<0.000001"`, and "more than you hold" validation against live balances.
  3. *Name* — byte-accurate 31-byte counter.
  4. `<ApprovalChecklist>` → `pack()`. Entries are sorted ascending by address (contract requirement)
     once in a `useMemo`. After mining, the `Packed` log is decoded from the receipt to navigate
     straight to `/bundle/<id>`.
- **`/bundle/[tokenId]` (client)** — batched reads of `getBasket`, `bundleMeta`, `ownerOf`, `tokenURI`,
  plus per-token `uiMultiplier()` for the ERC-8056 share-equivalent column
  (`shares = amount * mult / 1e18`). The image is rendered **only** if it is the renderer's own inline
  SVG (`image.startsWith("data:image/svg+xml")`) — never an arbitrary URL from chain data.
  Redeem is **simulate-first**:

  ```ts
  try { await client.simulateContract({ address: deployment.stockPack, abi: stockPackAbi, functionName: "unpack", args: [tokenId], account: address }); }
  catch (e) { setNeedsEmergency(true); setError(`Atomic unpack would fail: ${shortError(e)}`); return; }
  const hash = await writeContractAsync({ ..., functionName: emergency ? "emergencyUnpack" : "unpack", args: [tokenId] });
  ```
  The "Emergency unpack" button appears only after a failed simulation.
- **`/my` (client)** — `GET /api/bundles?owner=…&limit=50` (poll 15 s) + `ClaimsPanel` which reads
  `claimable(address, token)` for every *listed* token (poll 10 s) and offers `claim(token, address)`.

### 6.4 Approvals — `components/ApprovalChecklist.tsx`

Sequential per-token ERC-20 approvals (the tier every wallet supports). Exact-amount by default;
unlimited only if the user ticks the checkbox:

```ts
writeContract({ address: s.address, abi: erc20Abi, functionName: "approve",
                args: [deployment.stockPack, unlimited ? 2n ** 256n - 1n : s.amount] });
// readiness: allowance(owner, stockPack) >= amount for every entry, polled every 4 s → unlocks "Seal the bundle"
```

(Exact-amount approvals are also what keeps MetaMask/Blockaid from showing the "unlimited spending
cap" warning; the unlimited checkbox is the only source of that warning.)

### 6.5 Live preview — `components/LiveCardPreview.tsx`

Calls `renderer.previewSVG(tokens, amounts, name, creator)` via `useReadContract` and inlines the
result as `data:image/svg+xml;utf8,…`. Because hue depends only on `(name, creator)`, the preview is
pixel-identical to the minted card. Shows an explicit red "Preview unavailable" state if the RPC call fails.

### 6.6 Indexer — `web/lib/indexer.ts` + `web/lib/db.ts`

Mongo collections: `bundles` (`_id = tokenId`, `name, creator, owner, tokens[], amounts[] (decimal strings), sealedAt, status: live|redeemed|emergency, blockNumber, txHash`),
`activity` (`_id = "${block}-${logIndex}"`, idempotent), `cursors` (`_id = chainId`, `lastBlock`).
The Mongo client is cached on `globalThis` for warm-lambda reuse.

```ts
const cursor = await cursors.findOne({ _id: chain.id });
const head   = await client.getBlockNumber();
let from = cursor ? BigInt(cursor.lastBlock) + 1n : BigInt(deployment.deployBlock);
while (from <= head) {
  const to = from + CHUNK > head ? head : from + CHUNK;            // CHUNK = 9_000n (public RPC getLogs cap)
  const logs = await client.getContractEvents({ address: deployment.stockPack, abi: stockPackAbi, fromBlock: from, toBlock: to });
  // Packed → upsert bundle (owner=creator, status live, sealedAt from getBlock)
  // Transfer (non-mint/burn) → $set owner; Unpacked → status redeemed; EmergencyUnpacked → status emergency; Claimed → activity only
  await cursors.updateOne({ _id: chain.id }, { $set: { lastBlock: Number(to) } }, { upsert: true });
  from = to + 1n;
}
```

`queryBundles()` is the **single read path**: with `MONGODB_URI` it runs `await sync()` (cheap
incremental catch-up) then a Mongo `find().sort({_id:-1}).limit()`; without it, `scanBundles()` walks
the chain from `deployBlock` on every request (fine for demos, slows as the chain grows).
The `/api/sync` cron (every 5 min, `vercel.json`) is therefore a keep-warm/backfill — freshness is a
read-path property, which is why the client no longer pings `/api/sync` after transactions.

### 6.7 API routes

| Route | Behavior |
|---|---|
| `GET /api/sync` | Cron-only. `Authorization: Bearer <CRON_SECRET>` checked with `timingSafeEqual` (header only — never query string). 503 if secret unset (fail closed), 401 if wrong, 200 `{ok:false, reason}` if no Mongo, 502 generic on failure (details only in server logs). |
| `GET /api/bundles?owner&status&id&limit` | Validated (`^0x[0-9a-fA-F]{40}$`, `^\d{1,10}$`, status enum, limit clamped 1–50, NaN-safe). `id` → `{bundle}`; else `{bundles}`. Generic 502 on upstream failure. |
| `POST /api/refresh/[tokenId]` | OpenSea metadata-refresh proxy (mainnet only, 501 without `OPENSEA_API_KEY`). In-memory throttle: 5 min per token (bounded map, 512 keys) + global 10 calls/min. Key never leaves the server. |
| `GET /api/assets` | Official Robinhood Stock Token registry (`api.robinhood.com/rhj/assets`), filtered to active chain-4663 deployments and mapped to `{symbol, name, address, decimals, logoUrl}`. Returns `{tokens: []}` unless `registryEnabled` (mainnet + real-token flag). Upstream fetch `revalidate: 300`; response `s-maxage=300`. 502 generic on failure. See §6.2a. |
| `GET /api/og/[tokenId]` | 1200×630 PNG via `next/og` (X/Farcaster won't unfurl SVG). Reads `getBasket`/`bundleMeta` on-chain — burned/unminted ids 404. Same hue formula as the SVG. `Cache-Control: public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800` (basket can't change while live). |

> Gap: nothing sets `openGraph.images` to `/api/og/[tokenId]` yet (bundle page is a client component
> without `generateMetadata`). Wire this for rich social unfurls.

### 6.8 Security headers — `web/next.config.ts`

```ts
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https:",            // on-chain SVG arrives as data: URIs
  "font-src 'self' data:",
  `connect-src 'self' https: wss:${isLocalChain ? " http://127.0.0.1:* http://localhost:* ws://127.0.0.1:* ws://localhost:*" : ""}`,
  "frame-src https://verify.walletconnect.com https://verify.walletconnect.org",
  "frame-ancestors 'none'", "object-src 'none'", "base-uri 'self'", "form-action 'self'",
].join("; ");
// + HSTS (2y, preload), nosniff, X-Frame-Options DENY, Referrer-Policy strict-origin-when-cross-origin, Permissions-Policy, poweredByHeader: false
```

`frame-ancestors 'none'` is the clickjacking defense for the approve/unpack buttons. Localhost RPC is
allowed in `connect-src` only when `NEXT_PUBLIC_CHAIN=local`.

### 6.9 Off-chain/on-chain parity — `web/lib/display.ts`

`sanitizeName`, `accentHue` (`keccak256(encodePacked(["string","address"], [sanitizeName(name), creator])) % 360`),
`formatAmount`, `sealedDate` reimplement the contract's exact logic so `BundleCard` (CSS replica for grids)
and the OG route render matching art with zero RPC calls. If you change `SVGCard.formatAmount` or the
hue formula, change `display.ts` in the same commit and update `test_formatAmount_dustHonesty`.

---

## 7. End-to-end flows

**Mint**
1. User picks tokens/amounts/name on `/create`; entries sorted ascending by address.
2. `ApprovalChecklist`: `approve(stockPack, amount)` per token until `allowance ≥ amount` for all.
3. `pack(name, tokens, amounts)` → contract pulls each token, verifies exact delta, stores basket,
   bumps `totalEscrowed`, emits `Packed`, `_mint`s id to caller.
4. Frontend decodes `Packed` from the receipt → `/bundle/<id>`; indexer picks it up on the next read.

**Trade** — the card is a plain ERC-721: wallet-to-wallet transfer, OpenSea (Seaport 1.6 is predeployed;
OpenSea indexes mainnet only), or any P2P swap. Ownership moves; the basket does not change.

**Redeem** — holder calls `unpack(id)` (or `unpackTo(id, cleanAddress)`). Card burns; exact tokens
arrive in one tx. Works from the dApp, the explorer's verified-contract Write tab, `cast`, or any
wallet — **the site is never required**.

**Frozen leg** — simulation fails → `emergencyUnpack(id)` (no external calls) → per-token `claim()`
from `/my` (or directly) as each token becomes transferable.

---

## 8. Deployment state & operations

| Chain | Status |
|---|---|
| Local anvil `31337` | dev key 0 is artist/deployer; `deployments/31337*.json` checked in |
| Testnet `46630` | escrow `0x52BaEB6b67Ca9ba9D168c7E63a6fFe81Da6ef387` (Blockscout-verified); renderer currently live: `0x0dB0E06AD51582847EBB1EaC537A95E334865969` (rich description + `external_url` + artist-updatable `baseUrl`; Blockscout-verified; deployment JSONs updated); artist = deployer `0xfDD9…0DB6`; `deployBlock 111348241` |
| Mainnet `4663` | **deployed 2026-09-02** (production profile, 10k runs): escrow `0x52BaEB6b67Ca9ba9D168c7E63a6fFe81Da6ef387`, renderer `0xB325a01A1AEF6f05cb3E6A1197459be6bc164c0D` (mutable `baseUrl` = `https://stock-pack.vercel.app`), artist = owner MetaMask `0x600f94e748fb3cab8AFfc5Ab68c1e5Bf01e603a8`, deployer `0xfDD9…0DB6` (nonces 0/1 → same addresses as testnet), `deployBlock 52678077`, 0.0027 ETH total gas. Verified exact-match on Sourcify (mainnet Blockscout API is Cloudflare-challenged; it imports from Sourcify). `lockRenderer()` due 2026-09-16 |

Hosting: Vercel project (root dir `web/`), production at `https://stock-pack.vercel.app`, env
`NEXT_PUBLIC_CHAIN=mainnet` + `NEXT_PUBLIC_ENABLE_REAL_TOKENS=true` (Production; Preview stays `testnet`), `MONGODB_URI` (self-hosted MongoDB on a VPS), `MONGODB_DB`, `CRON_SECRET`. Bundle reads filter on `chainId` so leftover testnet docs in the shared DB never surface on mainnet.
Verified live: strict CSP/headers, `/api/sync` 401 unauthenticated, OG PNGs for live bundles, Mongo reads < 1 s.

Chain facts: RPC `https://rpc.{mainnet,testnet}.chain.robinhood.com`; explorer/verifier
`explorer.testnet.chain.robinhood.com` (mainnet: `robinhoodchain.blockscout.com`); faucet
`faucet.testnet.chain.robinhood.com` (0.01 ETH + 5 of each real testnet Stock Token, 24 h cooldown);
Permit2 / Multicall3 / Seaport 1.6 predeployed; Stock Tokens = ERC-20 + ERC-8056 `uiMultiplier`.

### Pre-mainnet checklist (state on 2026-09-02)

- ✅ Security audit passed (findings addressed — re-verify each is in-repo before deploy).
- ✅ Legal review cleared wrap-and-trade; counsel recommended geofencing for the real-token flag — owner decided (2026-09-02) to ship **without** a geofence.
- ⏳ Apply incoming testnet bug reports; re-run full flow on testnet.
- ⏳ MongoDB hardening: scoped `readWrite` user exists; still needed — update Vercel `MONGODB_URI` to it, rotate the old admin password, enable TLS + firewall on the VPS, create query indexes (`bundles.owner`, `bundles.status`, `activity.tokenId`).
- ✅ Renderer `baseUrl` is artist-updatable forever (`setBaseUrl`), so a later custom domain needs no redeploy or pre-lock timing.
- ⏳ Wire `openGraph.images` → `/api/og/[tokenId]`.
- ✅ Deployed chain 4663 with `[profile.production]` (2026-09-02); Sourcify-verified; `deployments/4663.json` copied to web; Vercel production on mainnet + real tokens. `SmokeTest.s.sol` needs mocks so it was not run — read-only checks (contractURI, previewSVG with real WETH/USDG) pass; first real pack/unpack is to be done by the owner from the dApp.
- ⏳ `lockRenderer()` from the artist wallet by 2026-09-16.

---

## 9. Threat model summary (what an agent must not break)

1. **Redemption is `ownerOf`-only.** Never add approval/operator-based burn paths.
2. **Baskets are immutable after mint.** No top-ups, partial withdrawals, or third-party mutation.
3. **Raw-unit ledger.** Never read live `balanceOf` for accounting; never let `totalEscrowed` drift from `live + unclaimed`.
4. **Fee-on-transfer rejected; rebasing unsupported.** Keep the strict delta check.
5. **`emergencyUnpack` makes zero external calls.** Do not add token calls to it.
6. **`_mint`, not `_safeMint`.** Documented footgun for naive contracts; do not "fix" by adding callbacks.
7. **Renderer is view-only and one-way lockable.** Any new admin surface over funds is out of scope.
8. **Nitro:** use `block.timestamp`, never `block.number`; deploy scripts use ArbSys for L2 height.
9. **Web:** generic API errors only; header-only cron auth; `img` only from renderer data URIs; exact-amount approvals by default; CSP `frame-ancestors 'none'`; never source `.env` secrets into commands or commit them.

Known trust assumptions outside the protocol's control: Robinhood runs the sequencer (can censor
any address, including the escrow); Stock Tokens are pausable/upgradeable by the issuer
(`emergencyUnpack`+`claim` is containment, not cure); Stock Tokens are Jersey-issued securities with
jurisdiction restrictions (enforce at UI/geo layer).

---

## 10. Common tasks for agents

- **Add a real mainnet token:** append to `REAL_MAINNET_STOCKS` / `REAL_MAINNET_COINS` in `web/lib/tokenlist.ts` with the canonical address from Robinhood's docs, correct `decimals`, and `category`.
- **Change card art or metadata text:** edit `SVGCard.sol` / `StockPackRenderer.sol`, update `Renderer.t.sol` assertions and `web/lib/display.ts` mirrors, `forge test`, deploy a new renderer, `setRenderer`, update both `46630.json` files, `forge verify-contract`.
- **Re-deploy web after contract deploy:** copy `deployments/<chainId>*.json` → `web/lib/deployments/`, commit, push (Vercel auto-builds from `main`, root `web/`).
- **Run everything locally:** `anvil` → `forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --private-key <anvil key 0> --broadcast` → `DeployMocks.s.sol` → copy JSONs → `cd web && NEXT_PUBLIC_CHAIN=local npm run dev`.
- **Debug "preview blank" / RPC blocked:** check `connect-src` in `next.config.ts` matches the chain mode; hard-refresh to drop a cached CSP.
- **Debug indexer hang:** confirm `deployBlock` is the L2 height (ArbSys), not an L1 number.
