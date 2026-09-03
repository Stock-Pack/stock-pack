# Pinned toolchain — verified against authoritative sources on 2026-09-01

| Component | Version | Verified via |
| --- | --- | --- |
| Foundry (forge/cast/anvil) | 1.8.1 (982849d) | `foundryup` install output |
| solc | 0.8.36 | `git ls-remote --tags ethereum/solidity` — v0.8.36 is the latest 0.8.x tag |
| OpenZeppelin Contracts | v5.7.0 | `git ls-remote --tags OpenZeppelin/openzeppelin-contracts` — latest stable v5 tag (v5.7.0-rc.0 exists above it; rc excluded) |
| forge-std | v1.16.2 | installed by `forge init` |
| EVM target | cancun | TLOAD probe via state-override `eth_call` on Robinhood testnet (chain 46630) returned success → EIP-1153 transient storage supported; `ReentrancyGuardTransient` is safe |
| Permit2 | canonical `0x000000000022D473030F116dDEE9F6B43aC78BA3` | `eth_getCode` on Robinhood mainnet (chain 4663) returned 18,306 hex chars of runtime code — deployed; fixture stored in `test/fixtures/permit2.bytecode.txt` |

Chain facts re-verified live: mainnet chain ID 4663 (`eth_chainId` = 0x1237 via research probe), testnet 46630 (`eth_chainId` = 0xb626 verified here).
