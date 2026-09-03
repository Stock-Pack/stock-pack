// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";

import {StockPackArt} from "../src/art/StockPackArt.sol";
import {ICardArt} from "../src/interfaces/ICardArt.sol";

/// @notice Dev tool: writes one reference card per edition, palette and finish into
///         web/public/art/ so the published rarity docs show real contract output
///         rather than mockups. Traits are addressed by constructing the seed bytes
///         directly, which is exact — no searching, no chance of an off-by-one caption.
contract RenderDocs is Script {
    StockPackArt art;

    /// @dev First seed byte in each edition's weight range.
    function _edByte(uint256 e) private pure returns (uint256) {
        uint16[10] memory starts = [uint16(0), 44, 82, 116, 148, 176, 202, 224, 240, 250];
        return starts[e];
    }

    function _palByte(uint256 p) private pure returns (uint256) {
        return p < 8 ? p * 27 : 216 + (p - 8) * 10;
    }

    function _finByte(uint256 f) private pure returns (uint256) {
        uint16[5] memory starts = [uint16(0), 120, 180, 224, 248];
        return starts[f];
    }

    function _seed(uint256 e, uint256 p, uint256 f) private pure returns (uint256) {
        return _edByte(e) | (_palByte(p) << 8) | (_finByte(f) << 16);
    }

    function run() external {
        art = new StockPackArt();

        string[10] memory eds =
            ["ledger", "strata", "tape", "mosaic", "terminal", "orbit", "splitflap", "monolith", "aurora", "guilloche"];
        string[12] memory pals = [
            "obsidian",
            "bone",
            "vellum",
            "cobalt",
            "oxide",
            "chlorophyll",
            "ash",
            "plum",
            "gilt",
            "glacier",
            "vapor",
            "ember"
        ];
        string[5] memory fins = ["matte", "etched", "foil", "gilded", "engraved"];

        // Editions: palette and finish held constant so only the composition varies.
        for (uint256 e; e < 10; ++e) {
            _write(string.concat("web/public/art/editions/", eds[e], ".svg"), _seed(e, 0, 0), 5);
        }
        // Palettes: Ledger + Matte throughout, so only the colour varies.
        for (uint256 p; p < 12; ++p) {
            _write(string.concat("web/public/art/palettes/", pals[p], ".svg"), _seed(0, p, 0), 5);
        }
        // Finishes: Strata + Obsidian throughout — a flat ground shows an overlay best.
        for (uint256 f; f < 5; ++f) {
            _write(string.concat("web/public/art/finishes/", fins[f], ".svg"), _seed(1, 0, f), 4);
        }
        console.log("wrote 27 reference cards to web/public/art/");
    }

    function _write(string memory path, uint256 seed, uint256 n) private {
        string[9] memory base = ["NVDA", "AAPL", "MSFT", "AMZN", "GOOGL", "META", "TSLA", "USDG", "WETH"];
        string[9] memory av = ["12", "8.5", "6", "4.25", "3", "2.75", "1.5", "1200", "0.5"];
        string[] memory syms = new string[](n);
        string[] memory amts = new string[](n);
        for (uint256 i; i < n; ++i) {
            syms[i] = base[i];
            amts[i] = av[i];
        }
        vm.writeFile(
            path,
            art.render(
                ICardArt.Card({
                    name: "Magnificent Seven",
                    tokenId: 1234,
                    sealedAt: 1788400000,
                    symbols: syms,
                    amountStrs: amts,
                    total: n,
                    seed: seed,
                    preview: false
                })
            )
        );
    }
}
