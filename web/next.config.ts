import type { NextConfig } from "next";

const isDev = process.env.NODE_ENV === "development";
// local anvil is plain http; testnet/mainnet RPCs are https-only
const isLocalChain = (process.env.NEXT_PUBLIC_CHAIN ?? "local") === "local";

/**
 * CSP notes:
 * - script-src: Next.js hydration needs inline scripts; dev mode additionally
 *   needs 'unsafe-eval' (react-refresh). Never 'unsafe-eval' in production.
 * - connect-src https:/wss:: the RPC endpoint is env-configurable and the
 *   WalletConnect relay uses wss — pinning hosts here would break deploys.
 * - img-src data:/blob:: on-chain SVG card art arrives as data: URIs; https:
 *   covers wallet icons served by RainbowKit/WalletConnect.
 * - frame-src: WalletConnect verification iframe only. frame-ancestors 'none'
 *   is the clickjacking defense for the approve/unpack buttons.
 */
const csp = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ""}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  `connect-src 'self' https: wss:${isLocalChain ? " http://127.0.0.1:* http://localhost:* ws://127.0.0.1:* ws://localhost:*" : ""}`,
  "frame-src https://verify.walletconnect.com https://verify.walletconnect.org",
  "frame-ancestors 'none'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: csp },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
