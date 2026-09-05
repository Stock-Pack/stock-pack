import type { Metadata, Viewport } from "next";
import { Inter_Tight, JetBrains_Mono } from "next/font/google";
import Link from "next/link";
import "./globals.css";
import "@rainbow-me/rainbowkit/styles.css";

import { Header } from "@/components/Header";
import { Logo } from "@/components/Logo";
import { TickerTape } from "@/components/TickerTape";
import { Web3Provider } from "@/components/Web3Provider";

/** Mono is the body face — it carries ~90% of the page, so it ships the full
 *  weight range. Inter Tight is display-only: 700 is the only weight used. */
const jetbrains = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains",
  display: "swap",
});

const interTight = Inter_Tight({
  subsets: ["latin"],
  weight: ["500", "700"],
  variable: "--font-inter-tight",
  display: "swap",
});

const TITLE = "StockPack — The On-Chain Ownership Layer for Tokenized Stocks & RWAs";
const DESCRIPTION =
  "The ownership layer for tokenized equity. Wrap real-world assets (RWA) into one composable on-chain " +
  "primitive, settled on an Arbitrum Layer 2. 100% backed, redeemable 1:1, no oracle, no fee, no admin over funds.";

export const metadata: Metadata = {
  title: TITLE,
  description: DESCRIPTION,
  // The category words carry real weight in search and in a shared link preview,
  // which is where most first impressions of this actually happen.
  keywords: [
    "RWA",
    "real-world assets",
    "tokenized stocks",
    "tokenized equities",
    "Layer 2",
    "on-chain settlement layer",
    "RWA layer",
    "composable primitive",
    "Arbitrum Orbit",
    "Robinhood Chain",
    "NFT",
    "DeFi",
  ],
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    type: "website",
    siteName: "StockPack",
  },
  twitter: { card: "summary_large_image", title: TITLE, description: DESCRIPTION },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

const FOOTER_LINKS: { heading: string; links: { label: string; href: string; external?: boolean }[] }[] = [
  {
    heading: "Product",
    links: [
      { label: "Bundles", href: "/" },
      { label: "Create", href: "/create" },
      { label: "My bundles", href: "/my" },
    ],
  },
  {
    heading: "Protocol",
    links: [
      { label: "How it works", href: "/#how" },
      { label: "Guarantees", href: "/#guarantees" },
      { label: "Contracts", href: "/#contracts" },
    ],
  },
  {
    heading: "Community",
    links: [
      { label: "GitHub", href: "https://github.com/Stock-Pack/stock-pack", external: true },
      { label: "Blockscout", href: "https://robinhoodchain.blockscout.com/", external: true },
      { label: "Brand assets", href: "/brand" },
    ],
  },
];

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${jetbrains.variable} ${interTight.variable}`}>
      <head>
        {/* The scroll reveal starts hidden and is un-hidden by an observer. With
            scripting off that observer never runs, so the sections must default
            back to visible rather than staying blank. */}
        <noscript>
          <style>{`.reveal{opacity:1 !important;transform:none !important}`}</style>
        </noscript>
      </head>
      <body className="min-h-screen antialiased">
        <Web3Provider>
          <TickerTape />
          <Header />
          <main>{children}</main>

          <footer className="border-t border-line">
            <div className="mx-auto grid max-w-[1280px] gap-10 px-6 py-14 sm:grid-cols-2 lg:grid-cols-[1.6fr_repeat(3,1fr)]">
              <div>
                <Logo />
                <p className="mini mt-3 max-w-xs">
                  Tokenized stock baskets sealed into one redeemable card on Robinhood Chain. Pack, trade, unpack
                  anytime.
                </p>
              </div>

              {FOOTER_LINKS.map((col) => (
                <div key={col.heading}>
                  <h3 className="eyebrow">{col.heading}</h3>
                  <ul className="mt-4 space-y-2">
                    {col.links.map((l) => (
                      <li key={l.label}>
                        <Link
                          href={l.href}
                          className="text-[12px] text-muted transition-colors hover:text-ink"
                          {...(l.external ? { target: "_blank", rel: "noreferrer noopener" } : {})}
                        >
                          {l.label}
                        </Link>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>

            <div className="border-t border-line">
              <p className="mx-auto max-w-[1280px] px-6 py-6 text-[11px] leading-[17px] text-muted">
                StockPack is an experimental, admin-less escrow contract. Every card is redeemable 1:1 for its exact
                escrowed balances, verifiable on-chain via <span className="text-ink">getBasket(tokenId)</span>. The
                chain sequencer is operated by Robinhood and can censor any address; tokenized stocks are
                issuer-pausable debt securities with jurisdiction restrictions. Nothing on this site is investment
                advice or an offer to buy or sell securities.
              </p>
            </div>
          </footer>
        </Web3Provider>
      </body>
    </html>
  );
}
