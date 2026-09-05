"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

import { Logo } from "@/components/Logo";
import { network } from "@/lib/contracts";

const NETWORK_LABEL =
  network === "mainnet" ? "Robinhood Chain" : network === "testnet" ? "RH Testnet" : "Local Anvil";

const NAV = [
  { href: "/", label: "Bundles" },
  { href: "/create", label: "Create" },
  { href: "/my", label: "Portfolio" },
  { href: "/#how", label: "How it works" },
  { href: "/#guarantees", label: "Guarantees" },
];

/**
 * RainbowKit's own button is a rounded pill with its own type stack. This drives the
 * same state machine through ConnectButton.Custom so the header keeps one square,
 * mono, black control in every state (disconnected / wrong network / connected).
 */
function WalletButton() {
  return (
    <ConnectButton.Custom>
      {({ account, chain, openAccountModal, openChainModal, openConnectModal, mounted }) => {
        const ready = mounted;
        const connected = ready && account && chain;
        return (
          <div
            {...(!ready && { "aria-hidden": true, style: { opacity: 0, pointerEvents: "none", userSelect: "none" } })}
          >
            {!connected ? (
              <button type="button" onClick={openConnectModal} className="btn btn-primary btn-sm">
                Connect wallet
              </button>
            ) : chain.unsupported ? (
              <button type="button" onClick={openChainModal} className="btn btn-sm bg-[var(--color-danger)] text-on-ink">
                Wrong network
              </button>
            ) : (
              <button type="button" onClick={openAccountModal} className="btn btn-ghost btn-sm">
                {account.displayName}
              </button>
            )}
          </div>
        );
      }}
    </ConnectButton.Custom>
  );
}

export function Header() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-bg/90 backdrop-blur">
      <div className="mx-auto flex h-[52px] max-w-[1280px] items-center gap-6 px-6">
        <Link href="/" className="shrink-0">
          <Logo />
        </Link>

        <nav className="hidden items-center gap-5 lg:flex">
          {NAV.map((item) => {
            const active = item.href === pathname;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`text-[13px] transition-colors hover:text-ink ${active ? "text-ink" : "text-muted"}`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="ml-auto flex shrink-0 items-center gap-3 sm:gap-4">
          <span className="mini hidden md:inline">{NETWORK_LABEL}</span>
          <WalletButton />
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={open ? "Close menu" : "Open menu"}
            className="btn btn-ghost grid h-[30px] w-[34px] shrink-0 place-items-center p-0 lg:hidden"
          >
            {/* three rules → an X, drawn rather than glyphed so the strokes match
                the hairlines everywhere else on the page */}
            <span aria-hidden className="relative block h-[9px] w-[13px]">
              <span
                className={`absolute left-0 block h-px w-full bg-ink transition-transform ${
                  open ? "top-1/2 rotate-45" : "top-0"
                }`}
              />
              <span className={`absolute top-1/2 left-0 block h-px w-full bg-ink ${open ? "opacity-0" : ""}`} />
              <span
                className={`absolute left-0 block h-px w-full bg-ink transition-transform ${
                  open ? "top-1/2 -rotate-45" : "bottom-0"
                }`}
              />
            </span>
          </button>
        </div>
      </div>

      {/* Below lg the nav is a disclosure sheet, so the bar stays one 52px row. */}
      {open && (
        <nav id="mobile-nav" className="border-t border-line bg-bg lg:hidden">
          {NAV.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              // the header never unmounts across routes, so the sheet has to be
              // dismissed by the navigation itself or it stays open over the new page
              onClick={() => setOpen(false)}
              className={`block border-b border-line-soft px-6 py-3 text-[13px] last:border-b-0 ${
                item.href === pathname ? "text-ink" : "text-muted"
              }`}
            >
              {item.label}
            </Link>
          ))}
          <p className="mini border-t border-line px-6 py-3 md:hidden">{NETWORK_LABEL}</p>
        </nav>
      )}
    </header>
  );
}
