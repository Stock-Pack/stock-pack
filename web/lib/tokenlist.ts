import { mockTokens, network, type Address } from "./contracts";

export type TokenCategory = "stock" | "coin" | "other"; // "other" = user-added by address, unverified

export type ListedToken = {
  symbol: string;
  address: Address;
  decimals: number;
  verified: boolean;
  real: boolean; // a real Robinhood Stock Token (mainnet only, feature-flagged)
  category: TokenCategory;
  hasFaucet: boolean; // MockStockToken: the site can mint it directly
  name?: string;
  logoUrl?: string;
  faucetUrl?: string; // external faucet (Robinhood's testnet faucet) — link out, can't mint here
};

/** Robinhood's own testnet faucet: 0.01 ETH + 5 of each testnet Stock Token, 24 h cooldown. */
export const ROBINHOOD_TESTNET_FAUCET = "https://faucet.testnet.chain.robinhood.com";

/**
 * Official Robinhood testnet Stock Tokens (chain 46630) — the five the Robinhood faucet hands
 * out. Verified 2026-09-02 on the testnet explorer: all are EIP-1967 BeaconProxies created by
 * 0x2DD5b0Ea7c29006bA9450B9a4f3ADc234409e5Da sharing implementation
 * 0xBd14156E05c6AF28ad39aA53a2AB8eB9CDf657DA, with verified source. The testnet explorer
 * lists 50+ counterfeit "PLTR"s alone, so exact addresses matter even for play money.
 */
const REAL_TESTNET_STOCKS: { symbol: string; name: string; address: Address }[] = [
  { symbol: "TSLA", name: "Tesla", address: "0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E" },
  { symbol: "AMD", name: "AMD", address: "0x71178BAc73cBeb415514eB542a8995b82669778d" },
  { symbol: "AMZN", name: "Amazon", address: "0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02" },
  { symbol: "NFLX", name: "Netflix", address: "0x3b8262A63d25f0477c4DDE23F83cfe22Cb768C93" },
  { symbol: "PLTR", name: "Palantir Technologies", address: "0x1FBE1a0e43594b3455993B5dE5Fd0A7A266298d0" },
];

/**
 * Canonical Robinhood Stock Token addresses on mainnet (chain 4663), from the official
 * registry at docs.robinhood.com/chain/contracts (verified 2026-09-01). Counterfeit
 * tickers are abundant on this chain — anything not on this list renders with a loud
 * "unverified" warning.
 *
 * REAL-STOCK GATE: these only appear when NEXT_PUBLIC_ENABLE_REAL_TOKENS is "true".
 * Robinhood Stock Tokens are Jersey-issued debt securities restricted from
 * US/UK/CA/CH/UAE persons — do not enable without legal review and geofencing.
 */
const REAL_MAINNET_STOCKS: { symbol: string; address: Address }[] = [
  { symbol: "NVDA", address: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC" },
  { symbol: "AAPL", address: "0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9" },
  { symbol: "MSFT", address: "0xe93237C50D904957Cf27E7B1133b510C669c2e74" },
  { symbol: "TSLA", address: "0x322F0929c4625eD5bAd873c95208D54E1c003b2d" },
  { symbol: "AMZN", address: "0x12f190a9F9d7D37a250758b26824B97CE941bF54" },
  { symbol: "GOOGL", address: "0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3" },
  { symbol: "META", address: "0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35" },
  { symbol: "SPY", address: "0x117cc2133c37B721F49dE2A7a74833232B3B4C0C" },
  { symbol: "QQQ", address: "0xD5f3879160bc7c32ebb4dC785F8a4F505888de68" },
];

/**
 * Canonical freely-transferable COINS on Robinhood Chain mainnet (verified 2026-09-01).
 * Unlike the stock tokens these are NOT restricted securities — USDG is the Global Dollar
 * stablecoin, WETH is wrapped ETH — so they are shown WITHOUT the real-stock legal gate.
 * The escrow accepts any standard ERC-20 (fee-on-transfer rejected, rebasing unsupported);
 * this list is just the curated/verified set the picker surfaces by default.
 */
const REAL_MAINNET_COINS: { symbol: string; address: Address; decimals: number }[] = [
  { symbol: "USDG", address: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168", decimals: 6 },
  { symbol: "WETH", address: "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73", decimals: 18 },
];

const realStocksEnabled = process.env.NEXT_PUBLIC_ENABLE_REAL_TOKENS === "true";

/** Mock tokens whose symbol marks them as coins rather than stocks (local/testnet demos).
 *  All mocks are deployed with 18 decimals (MockStockToken.faucet mints 100e18). */
const MOCK_COIN_SYMBOLS = new Set(["mWETH", "mUSDG", "mUSDC", "mDAI"]);

export function listedTokens(): ListedToken[] {
  const mocks: ListedToken[] = mockTokens.map((t) => ({
    symbol: t.symbol,
    address: t.address,
    decimals: 18,
    verified: true,
    real: false,
    category: MOCK_COIN_SYMBOLS.has(t.symbol) ? ("coin" as const) : ("stock" as const),
    hasFaucet: true,
  }));

  if (network === "mainnet") {
    const coins: ListedToken[] = REAL_MAINNET_COINS.map((t) => ({
      symbol: t.symbol,
      address: t.address,
      decimals: t.decimals,
      verified: true,
      real: true,
      category: "coin",
      hasFaucet: false,
    }));
    const stocks: ListedToken[] = realStocksEnabled
      ? REAL_MAINNET_STOCKS.map((t) => ({
          symbol: t.symbol,
          address: t.address,
          decimals: 18,
          verified: true,
          real: true,
          category: "stock" as const,
          hasFaucet: false,
        }))
      : [];
    // coins are ungated; stocks gated behind the legal flag; mocks appear if any were deployed
    return [...stocks, ...coins, ...mocks];
  }

  if (network === "testnet") {
    // Robinhood's testnet stocks are play tokens, not securities — no legal gate, no REAL badge
    const testnetStocks: ListedToken[] = REAL_TESTNET_STOCKS.map((t) => ({
      symbol: t.symbol,
      name: t.name,
      address: t.address,
      decimals: 18,
      verified: true,
      real: false,
      category: "stock" as const,
      hasFaucet: false,
      faucetUrl: ROBINHOOD_TESTNET_FAUCET,
    }));
    return [...testnetStocks, ...mocks];
  }

  return mocks;
}

/** Whether the mainnet registry (api.robinhood.com/rhj/assets) may be consulted at all. */
export const registryEnabled = network === "mainnet" && realStocksEnabled;

export function findListed(address: string): ListedToken | undefined {
  return listedTokens().find((t) => t.address.toLowerCase() === address.toLowerCase());
}
