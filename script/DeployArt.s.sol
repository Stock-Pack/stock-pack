// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {StockPack} from "../src/StockPack.sol";
import {StockPackArt} from "../src/art/StockPackArt.sol";
import {StockPackRenderer} from "../src/StockPackRenderer.sol";
import {IStockPackRenderer} from "../src/interfaces/IStockPackRenderer.sol";

/// @notice Deploys a new artwork + renderer pair WITHOUT pointing the escrow at it.
///
///         UpgradeRenderer does both in one broadcast, which forces the whole thing —
///         six contract deployments — to be signed by the escrow's `artist`. On mainnet
///         that key is a hardware/browser wallet holding real funds, and there is no
///         reason for it to pay for the deployments too.
///
///         This half can be broadcast by any funded address. The escrow is untouched
///         and keeps serving the old art until the artist sends the single
///         `setRenderer` call, so a failure here costs gas and nothing else.
///
///         Addresses land in deployments/<chainid>.json under `pendingRenderer` /
///         `pendingArt` — deliberately not `renderer`/`art`, which must keep describing
///         what the escrow actually points at until the swap lands.
contract DeployArt is Script {
    using stdJson for string;

    function run() external returns (address artAddr, address rendererAddr) {
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory file = vm.readFile(path);
        StockPack pack = StockPack(file.readAddress(".stockPack"));
        require(!pack.rendererLocked(), "renderer is locked - nothing can be swapped in");

        string memory fallbackUrl =
            vm.keyExistsJson(file, ".baseUrl") ? file.readString(".baseUrl") : "https://stock-pack.vercel.app";
        string memory baseUrl = vm.envOr("BASE_URL", fallbackUrl);

        vm.startBroadcast();
        StockPackArt art = new StockPackArt();
        StockPackRenderer renderer = new StockPackRenderer(address(pack), address(art), baseUrl);
        vm.stopBroadcast();

        // Prove the pair works before anyone is asked to sign the swap: a renderer that
        // reverts here would brick every marketplace listing the moment it went live.
        require(address(renderer.stockPack()) == address(pack), "renderer not bound to this escrow");
        require(bytes(IStockPackRenderer(address(renderer)).contractURI()).length > 0, "contractURI dead");

        artAddr = address(art);
        rendererAddr = address(renderer);

        // Only record addresses on a real broadcast. `vm.writeJson` also runs during a
        // dry run, so simulating this script used to overwrite the deployment file with
        // an address that was never deployed — mainnet's record pointed at
        // 0x8Cbc…ab3b, a contract that has no code, until it was reconciled by hand.
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console.log("dry run - deployment file left untouched");
            return (artAddr, rendererAddr);
        }

        vm.writeJson(vm.toString(rendererAddr), path, ".pendingRenderer");
        vm.writeJson(vm.toString(artAddr), path, ".pendingArt");

        console.log("art          ", artAddr);
        console.log("renderer     ", rendererAddr);
        console.log("escrow       ", address(pack));
        console.log("artist (must sign the swap)", pack.artist());
        console.log("NEXT: artist sends setRenderer(address) with the renderer above");
    }
}
