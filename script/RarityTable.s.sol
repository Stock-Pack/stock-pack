// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";

import {StockPackArt} from "../src/art/StockPackArt.sol";

/// @notice Dev tool: samples the real trait function across every possible seed byte and
///         prints the exact distribution, so the published rarity tables are measured
///         from the contract rather than restated from intent. The three trait bytes are
///         independent, so enumerating 0..255 for each is exhaustive, not a sample.
contract RarityTable is Script {
    function run() external {
        StockPackArt art = new StockPackArt();

        uint256[10] memory eds;
        uint256[12] memory pals;
        uint256[5] memory fins;

        for (uint256 b; b < 256; ++b) {
            (uint256 e,,) = art.traits(b); // edition reads seed byte 0
            eds[e]++;
            (, uint256 p,) = art.traits(b << 8); // palette reads byte 1
            pals[p]++;
            (,, uint256 f) = art.traits(b << 16); // finish reads byte 2
            fins[f]++;
        }

        console.log("EDITION counts out of 256:");
        for (uint256 i; i < 10; ++i) {
            (string memory n,,,) = art.traitNames(i, 0, 0);
            console.log(string.concat("  ", n), eds[i]);
        }
        console.log("PALETTE counts out of 256:");
        for (uint256 i; i < 12; ++i) {
            (, string memory n,,) = art.traitNames(0, i, 0);
            console.log(string.concat("  ", n), pals[i]);
        }
        console.log("FINISH counts out of 256:");
        for (uint256 i; i < 5; ++i) {
            (,, string memory n,) = art.traitNames(0, 0, i);
            console.log(string.concat("  ", n), fins[i]);
        }

        // Tier is a function of the three indices, so weight every combination by the
        // product of its trait counts to get the exact share out of 256^3.
        uint256 common;
        uint256 uncommon;
        uint256 rare;
        uint256 mythic;
        for (uint256 e; e < 10; ++e) {
            for (uint256 p; p < 12; ++p) {
                for (uint256 f; f < 5; ++f) {
                    uint256 w = eds[e] * pals[p] * fins[f];
                    (,,, string memory t) = art.traitNames(e, p, f);
                    bytes32 h = keccak256(bytes(t));
                    if (h == keccak256("Common")) common += w;
                    else if (h == keccak256("Uncommon")) uncommon += w;
                    else if (h == keccak256("Rare")) rare += w;
                    else mythic += w;
                }
            }
        }
        uint256 total = 256 * 256 * 256;
        console.log("TIER shares, parts per million:");
        console.log("  Common  ", common * 1e6 / total);
        console.log("  Uncommon", uncommon * 1e6 / total);
        console.log("  Rare    ", rare * 1e6 / total);
        console.log("  Mythic  ", mythic * 1e6 / total);
        console.log("  sum check", common + uncommon + rare + mythic == total ? 1 : 0);
    }
}
