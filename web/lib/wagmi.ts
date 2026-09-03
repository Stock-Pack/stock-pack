"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { injectedWallet, rainbowWallet, walletConnectWallet } from "@rainbow-me/rainbowkit/wallets";
import { http } from "wagmi";

import { chain, clientRpcUrl } from "./contracts";

export const wagmiConfig = getDefaultConfig({
  appName: "StockPack",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "stockpack-dev-placeholder",
  // injectedWallet surfaces every EIP-6963-announced browser wallet (MetaMask, Phantom,
  // Rabby, …) as its own "Installed" entry — no SDK-based detection that can hang.
  wallets: [
    { groupName: "Installed in your browser", wallets: [injectedWallet] },
    { groupName: "Other options", wallets: [rainbowWallet, walletConnectWallet] },
  ],
  chains: [chain],
  transports: { [chain.id]: http(clientRpcUrl) },
  ssr: true,
});
