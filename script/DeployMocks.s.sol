// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script} from "forge-std/Script.sol";

import {StockPack} from "../src/StockPack.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";

/// @notice Deploys the demo tokens (six stocks + two coins) and seeds showcase bundles,
///         demonstrating that StockPack wraps any ERC-20 — stocks and coins alike.
///         Reads the escrow address from deployments/<chainid>.json (or STOCKPACK_ADDRESS
///         env override). Writes the token addresses to deployments/<chainid>.mocks.json.
contract DeployMocks is Script {
    // Indices 0..5 are stocks, 6..7 are coins. All 18-decimal (MockStockToken.faucet mints 100e18).
    string[8] internal names = [
        "Mock NVIDIA",
        "Mock Apple",
        "Mock Microsoft",
        "Mock Tesla",
        "Mock Amazon",
        "Mock Alphabet",
        "Mock Wrapped Ether",
        "Mock Global Dollar"
    ];
    string[8] internal symbols = ["mNVDA", "mAAPL", "mMSFT", "mTSLA", "mAMZN", "mGOOG", "mWETH", "mUSDG"];

    function run() external {
        address packAddr = vm.envOr("STOCKPACK_ADDRESS", address(0));
        if (packAddr == address(0)) {
            string memory j = vm.readFile(string.concat("deployments/", vm.toString(block.chainid), ".json"));
            packAddr = vm.parseJsonAddress(j, "$.stockPack");
        }
        StockPack pack = StockPack(packAddr);

        vm.startBroadcast();
        address[] memory toks = new address[](8);
        for (uint256 i; i < 8; ++i) {
            toks[i] = address(new MockStockToken(names[i], symbols[i], 18));
        }

        // ── #1: The Big Tech Bundle (1 mNVDA + 1 mAAPL + 1 mMSFT) ──
        _seed(pack, toks, _idx3(0, 1, 2), "The Big Tech Bundle", 1e18, 1e18, 1e18);
        // ── #2: EV & Cloud (2 mTSLA + 0.5 mAMZN) ──
        _seed(pack, toks, _idx2(3, 4), "EV & Cloud", 2e18, 5e17, 0);
        // ── #3: Blue Chips + ETH — a MIX of stocks and coins (1 mNVDA + 0.5 mWETH + 100 mUSDG) ──
        _seed(pack, toks, _idx3(0, 6, 7), "Blue Chips + ETH", 1e18, 5e17, 100e18);
        // ── #4: Full House (all six stocks) ──
        _seedAll(pack, toks);
        vm.stopBroadcast();

        // record token addresses for the frontend tokenlist
        string memory json = "mocks";
        for (uint256 i; i < 8; ++i) {
            vm.serializeAddress(json, symbols[i], toks[i]);
        }
        string memory out = vm.serializeUint(json, "chainId", block.chainid);
        vm.writeJson(out, string.concat("deployments/", vm.toString(block.chainid), ".mocks.json"));
    }

    function _idx3(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory idx) {
        idx = new uint256[](3);
        idx[0] = a;
        idx[1] = b;
        idx[2] = c;
    }

    function _idx2(uint256 a, uint256 b) private pure returns (uint256[] memory idx) {
        idx = new uint256[](2);
        idx[0] = a;
        idx[1] = b;
    }

    function _seed(
        StockPack pack,
        address[] memory toks,
        uint256[] memory idx,
        string memory name,
        uint256 a0,
        uint256 a1,
        uint256 a2
    ) private {
        uint256 n = idx.length;
        address[] memory tokens = new address[](n);
        uint256[] memory amounts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            tokens[i] = toks[idx[i]];
            amounts[i] = i == 0 ? a0 : i == 1 ? a1 : a2;
        }
        _sort(tokens, amounts);
        for (uint256 i; i < n; ++i) {
            MockStockToken(tokens[i]).mint(msg.sender, amounts[i]);
            MockStockToken(tokens[i]).approve(address(pack), amounts[i]);
        }
        pack.pack(name, tokens, amounts);
    }

    function _seedAll(StockPack pack, address[] memory toks) private {
        address[] memory tokens = new address[](6);
        uint256[] memory amounts = new uint256[](6);
        for (uint256 i; i < 6; ++i) {
            tokens[i] = toks[i];
            amounts[i] = (i + 1) * 25e16; // 0.25 .. 1.5
        }
        _sort(tokens, amounts);
        for (uint256 i; i < 6; ++i) {
            MockStockToken(tokens[i]).mint(msg.sender, amounts[i]);
            MockStockToken(tokens[i]).approve(address(pack), amounts[i]);
        }
        pack.pack("Full House", tokens, amounts);
    }

    function _sort(address[] memory tokens, uint256[] memory amounts) private pure {
        for (uint256 i = 1; i < tokens.length; ++i) {
            address t = tokens[i];
            uint256 a = amounts[i];
            uint256 j = i;
            while (j > 0 && tokens[j - 1] > t) {
                tokens[j] = tokens[j - 1];
                amounts[j] = amounts[j - 1];
                --j;
            }
            tokens[j] = t;
            amounts[j] = a;
        }
    }
}
