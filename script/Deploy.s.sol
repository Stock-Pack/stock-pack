// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {StockPack} from "../src/StockPack.sol";
import {StockPackArt} from "../src/art/StockPackArt.sol";
import {StockPackRenderer} from "../src/StockPackRenderer.sol";
import {IStockPackRenderer} from "../src/interfaces/IStockPackRenderer.sol";

/// @notice Deploys the protocol with the renderer↔escrow bootstrap:
///         1. precompute the StockPack address (deployer nonce + 1)
///         2. deploy the renderer bound to that address
///         3. deploy StockPack pointing at the renderer
///         4. assert the prediction held and tokenURI plumbing responds
///         Writes deployments/<chainid>.json for the frontend.
///
///         ARTIST_ADDRESS env (optional) sets the renderer-admin key; defaults to the
///         deployer. Use a hardware wallet / multisig for mainnet and lock within 14 days.
///         BASE_URL env (optional) seeds the dApp origin baked into metadata; the artist
///         can change it later with renderer.setBaseUrl(), even after lockRenderer().
contract Deploy is Script {
    function run() external returns (address packAddr, address rendererAddr) {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address artist = vm.envOr("ARTIST_ADDRESS", deployer);
        string memory baseUrl = vm.envOr("BASE_URL", string("https://stock-pack.vercel.app"));

        // Art first: it is a standalone pure contract, so the escrow-address prediction
        // below is taken *after* it lands and stays a simple nonce+1.
        StockPackArt art = new StockPackArt();
        address predicted = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        StockPackRenderer renderer = new StockPackRenderer(predicted, address(art), baseUrl);
        StockPack pack = new StockPack(address(renderer), artist);
        vm.stopBroadcast();

        require(address(pack) == predicted, "bootstrap: address prediction failed");
        require(address(renderer.stockPack()) == address(pack), "bootstrap: renderer not bound");
        // contractURI must respond before any public mint (OpenSea caches aggressively)
        require(bytes(IStockPackRenderer(address(renderer)).contractURI()).length > 0, "contractURI dead");

        packAddr = address(pack);
        rendererAddr = address(renderer);

        string memory json = "deployment";
        vm.serializeAddress(json, "stockPack", packAddr);
        vm.serializeAddress(json, "renderer", rendererAddr);
        vm.serializeAddress(json, "art", address(art));
        vm.serializeAddress(json, "artist", artist);
        vm.serializeString(json, "baseUrl", baseUrl);
        vm.serializeUint(json, "chainId", block.chainid);
        string memory out = vm.serializeUint(json, "deployBlock", _l2BlockNumber());
        vm.writeJson(out, string.concat("deployments/", vm.toString(block.chainid), ".json"));
    }

    /// @dev On Arbitrum Nitro chains (Robinhood Chain included) block.number is the
    ///      APPROXIMATE L1 BLOCK, ~100M behind the L2 chain height — recording it made
    ///      the frontend's from-deploy log scan sweep the whole gap. ArbSys (0x64)
    ///      returns the real L2 height; plain EVM chains (anvil) fall back to block.number.
    function _l2BlockNumber() private view returns (uint256) {
        (bool ok, bytes memory d) =
            address(0x0000000000000000000000000000000000000064).staticcall(abi.encodeWithSignature("arbBlockNumber()"));
        return ok && d.length == 32 ? abi.decode(d, (uint256)) : block.number;
    }
}
