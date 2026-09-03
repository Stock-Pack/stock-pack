// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";

import {StockPack} from "../src/StockPack.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";

/// @notice Live smoke test for a fresh deployment: faucet → pack → tokenURI →
///         unpack → emergencyUnpack → claim, all from the broadcasting key.
///         Run against testnet after Deploy + DeployMocks:
///         forge script script/SmokeTest.s.sol --rpc-url robinhood_testnet --account <keystore> --broadcast
contract SmokeTest is Script {
    function run() external {
        string memory chain = vm.toString(block.chainid);
        address packAddr =
            vm.parseJsonAddress(vm.readFile(string.concat("deployments/", chain, ".json")), "$.stockPack");
        string memory mocks = vm.readFile(string.concat("deployments/", chain, ".mocks.json"));
        address nvda = vm.parseJsonAddress(mocks, "$.mNVDA");
        address aapl = vm.parseJsonAddress(mocks, "$.mAAPL");
        StockPack pack = StockPack(packAddr);

        vm.startBroadcast();
        (, address me,) = vm.readCallers();

        MockStockToken(nvda).mint(me, 2e18);
        MockStockToken(aapl).mint(me, 2e18);
        MockStockToken(nvda).approve(packAddr, type(uint256).max);
        MockStockToken(aapl).approve(packAddr, type(uint256).max);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        (tokens[0], tokens[1]) = nvda < aapl ? (nvda, aapl) : (aapl, nvda);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        // pack → unpack round trip
        uint256 id1 = pack.pack("Smoke Bundle", tokens, amounts);
        require(pack.ownerOf(id1) == me, "smoke: not owner");
        require(bytes(pack.tokenURI(id1)).length > 100, "smoke: tokenURI dead");
        pack.unpack(id1);

        // emergency → claim path
        uint256 id2 = pack.pack("Smoke Emergency", tokens, amounts);
        pack.emergencyUnpack(id2);
        pack.claim(tokens[0], me);
        pack.claim(tokens[1], me);
        vm.stopBroadcast();

        require(pack.totalEscrowed(tokens[0]) >= 0, "unreachable"); // ledger readable
        console.log("SMOKE OK: pack/unpack/tokenURI/emergency/claim all live on chain", block.chainid);
        console.log("  ids:", id1, id2);
    }
}
