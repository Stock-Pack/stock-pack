// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {StockPack} from "../src/StockPack.sol";
import {StockPackArt} from "../src/art/StockPackArt.sol";
import {StockPackRenderer} from "../src/StockPackRenderer.sol";
import {IStockPackRenderer} from "../src/interfaces/IStockPackRenderer.sol";

/// @notice Swaps the renderer of an already-deployed StockPack (only possible while the
///         escrow's renderer pointer is unlocked). Must be broadcast from the `artist` key.
///         Reads the escrow address from deployments/<chainid>.json and rewrites the
///         `renderer` / `baseUrl` fields in place.
///
///         BASE_URL env (optional) seeds the new renderer; defaults to the value recorded
///         in the deployment file, then to https://stock-pack.vercel.app.
///
///         For a plain domain change there is no need for this script at all:
///         `cast send <renderer> "setBaseUrl(string)" https://new.domain --account <artist>`.
contract UpgradeRenderer is Script {
    using stdJson for string;

    function run() external returns (address rendererAddr) {
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory file = vm.readFile(path);
        StockPack pack = StockPack(file.readAddress(".stockPack"));
        require(!pack.rendererLocked(), "renderer is locked");

        string memory fallbackUrl =
            vm.keyExistsJson(file, ".baseUrl") ? file.readString(".baseUrl") : "https://stock-pack.vercel.app";
        string memory baseUrl = vm.envOr("BASE_URL", fallbackUrl);

        vm.startBroadcast();
        (, address sender,) = vm.readCallers();
        require(sender == pack.artist(), "broadcast from artist key");
        StockPackArt art = new StockPackArt();
        StockPackRenderer renderer = new StockPackRenderer(address(pack), address(art), baseUrl);
        pack.setRenderer(address(renderer));
        vm.stopBroadcast();

        require(pack.renderer() == address(renderer), "setRenderer did not take");
        require(bytes(IStockPackRenderer(address(renderer)).contractURI()).length > 0, "contractURI dead");
        rendererAddr = address(renderer);

        // See DeployArt: writeJson fires on dry runs too, and a simulated address in
        // the deployment record is worse than no record at all.
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console.log("dry run - deployment file left untouched");
            return rendererAddr;
        }

        vm.writeJson(vm.toString(rendererAddr), path, ".renderer");
        vm.writeJson(vm.toString(address(art)), path, ".art");
        vm.writeJson(baseUrl, path, ".baseUrl");
    }
}
