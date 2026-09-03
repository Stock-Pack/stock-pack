// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";

import {StockPackArt} from "../src/art/StockPackArt.sol";
import {ICardArt} from "../src/interfaces/ICardArt.sol";

/// @notice Dev tool: renders the card art across editions and basket shapes straight
///         to art-out/*.svg so the generator can be reviewed by eye, and prints the
///         byte size of each so the tokenURI budget is measured rather than guessed.
///         Never broadcast; run with `forge script script/RenderSamples.s.sol`.
contract RenderSamples is Script {
    StockPackArt art;

    function run() external {
        art = new StockPackArt();

        string[10] memory edNames =
            ["Ledger", "Strata", "Tape", "Mosaic", "Terminal", "Orbit", "Splitflap", "Monolith", "Aurora", "Guilloche"];
        uint256[10] memory seedFor; // one seed per edition, found by search below
        bool[10] memory found;

        // walk seeds until each edition has an example, so the sheet covers all six
        for (uint256 s = 1; s < 12000; ++s) {
            uint256 seed = uint256(keccak256(abi.encodePacked(s)));
            (uint256 ed,,) = art.traits(seed);
            if (!found[ed]) {
                found[ed] = true;
                seedFor[ed] = seed;
            }
        }

        uint256 worst;
        for (uint256 e; e < 10; ++e) {
            for (uint256 v; v < 4; ++v) {
                uint256 n = v == 0 ? 1 : v == 1 ? 3 : v == 2 ? 7 : 16;
                string memory svg = _render(seedFor[e], n, v == 3);
                uint256 len = bytes(svg).length;
                if (len > worst) worst = len;
                vm.writeFile(string.concat("art-out/", edNames[e], "-", vm.toString(n), ".svg"), svg);
                console.log(string.concat(edNames[e], " n=", vm.toString(n), " bytes="), len);
            }
        }
        console.log("worst-case raw SVG bytes:", worst);

        // Gallery: many seeds against realistic baskets, so the sheet shows the true
        // distribution of editions, palettes and finishes rather than one of each.
        string[8] memory names =
            ["Magnificent Seven", "EV & Cloud", "Blue Chips + ETH", "All In", "Semis", "Index Core", "Dust", "Barbell"];
        for (uint256 i; i < 32; ++i) {
            uint256 seed = uint256(keccak256(abi.encodePacked("gallery", i)));
            uint256 n = 1 + (i * 5 + 3) % 9;
            vm.writeFile(
                string.concat("art-out/gallery/", vm.toString(i), ".svg"), _gallery(seed, n, names[i % 8], 100 + i)
            );
        }
        console.log("gallery written: 32 cards");
    }

    function _gallery(uint256 seed, uint256 n, string memory name, uint256 tokenId)
        private
        view
        returns (string memory)
    {
        string[9] memory base = ["NVDA", "AAPL", "MSFT", "AMZN", "GOOGL", "META", "TSLA", "USDG", "WETH"];
        string[9] memory av = ["12", "8.5", "6", "4.25", "3", "2.75", "1.5", "1200", "0.006721"];
        string[] memory syms = new string[](n);
        string[] memory amts = new string[](n);
        for (uint256 i; i < n; ++i) {
            syms[i] = base[i % 9];
            amts[i] = av[i % 9];
        }
        return art.render(
            ICardArt.Card({
                name: name,
                tokenId: tokenId,
                sealedAt: 1788400000,
                symbols: syms,
                amountStrs: amts,
                total: n,
                seed: seed,
                preview: false
            })
        );
    }

    function _render(uint256 seed, uint256 n, bool longSyms) private view returns (string memory) {
        string[] memory syms = new string[](n);
        string[] memory amts = new string[](n);
        string[7] memory base = ["NVDA", "AAPL", "MSFT", "AMZN", "GOOGL", "META", "TSLA"];
        string[7] memory av = ["12", "8.5", "6", "4.25", "3", "2.75", "1.5"];
        for (uint256 i; i < n; ++i) {
            syms[i] = longSyms ? "mLONGSYMBOL" : base[i % 7];
            amts[i] = longSyms ? "1234567.89" : av[i % 7];
        }
        return art.render(
            ICardArt.Card({
                name: longSyms ? "abcdefghijklmnopqrstuvwxyzabcde" : "Magnificent Seven",
                tokenId: 1234,
                sealedAt: 1788400000,
                symbols: syms,
                amountStrs: amts,
                total: n,
                seed: seed,
                preview: false
            })
        );
    }
}
