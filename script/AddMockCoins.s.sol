// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script} from "forge-std/Script.sol";

import {StockPack} from "../src/StockPack.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";

/// @notice Append-only upgrade for an already-deployed demo: deploys two mock COINS
///         (mWETH, mUSDG) and seeds one mixed stock+coin bundle, WITHOUT touching the
///         existing stock mocks or their showcase bundles. Merges the two new addresses
///         into deployments/<chainid>.mocks.json. Run once per network that already ran
///         DeployMocks before the coins category existed.
contract AddMockCoins is Script {
    function run() external {
        string memory chain = vm.toString(block.chainid);
        string memory dep = vm.readFile(string.concat("deployments/", chain, ".json"));
        StockPack pack = StockPack(vm.parseJsonAddress(dep, "$.stockPack"));

        // an existing verified stock, to demonstrate a mixed bundle
        string memory mocks = vm.readFile(string.concat("deployments/", chain, ".mocks.json"));
        address nvda = vm.parseJsonAddress(mocks, "$.mNVDA");

        vm.startBroadcast();
        address weth = address(new MockStockToken("Mock Wrapped Ether", "mWETH", 18));
        address usdg = address(new MockStockToken("Mock Global Dollar", "mUSDG", 18));

        // Mixed bundle: 1 mNVDA + 0.5 mWETH + 100 mUSDG (sorted ascending for the escrow).
        address[] memory tokens = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        tokens[0] = nvda;
        amounts[0] = 1e18;
        tokens[1] = weth;
        amounts[1] = 5e17;
        tokens[2] = usdg;
        amounts[2] = 100e18;
        _sort(tokens, amounts);
        for (uint256 i; i < 3; ++i) {
            MockStockToken(tokens[i]).mint(msg.sender, amounts[i]);
            MockStockToken(tokens[i]).approve(address(pack), amounts[i]);
        }
        pack.pack("Blue Chips + ETH", tokens, amounts);
        vm.stopBroadcast();

        // merge the two new coin addresses into the existing mocks.json
        string memory path = string.concat("deployments/", chain, ".mocks.json");
        vm.writeJson(vm.toString(weth), path, "$.mWETH");
        vm.writeJson(vm.toString(usdg), path, "$.mUSDG");
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
