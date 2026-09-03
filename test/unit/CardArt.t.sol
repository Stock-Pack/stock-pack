// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {StockPackArt} from "../../src/art/StockPackArt.sol";
import {ICardArt} from "../../src/interfaces/ICardArt.sol";

/// @notice Regression cover for the generative card art. Every case here is a defect
///         that actually occurred while building it, not a hypothetical.
contract CardArtTest is Test {
    uint256 internal constant EDITIONS = 10;

    StockPackArt internal art;

    function setUp() public {
        art = new StockPackArt();
    }

    function _card(uint256 seed, uint256 n, string memory sym, string memory name, uint256 tokenId)
        internal
        pure
        returns (ICardArt.Card memory c)
    {
        string[] memory syms = new string[](n);
        string[] memory amts = new string[](n);
        for (uint256 i; i < n; ++i) {
            syms[i] = sym;
            amts[i] = "12.5";
        }
        c = ICardArt.Card({
            name: name,
            tokenId: tokenId,
            sealedAt: 1788400000,
            symbols: syms,
            amountStrs: amts,
            total: n,
            seed: seed,
            preview: false
        });
    }

    /// @dev Finds a seed whose traits select `edition`.
    function _seedFor(uint256 edition) internal view returns (uint256) {
        for (uint256 s = 1; s < 9000; ++s) {
            uint256 seed = uint256(keccak256(abi.encodePacked(s)));
            (uint256 ed,,) = art.traits(seed);
            if (ed == edition) return seed;
        }
        revert("no seed for edition");
    }

    /// Every edition must produce a well-formed document at every basket size. The
    /// original layouts composed only around n=7 and collapsed at the extremes.
    function test_allEditionsRenderAtEveryBasketSize() public view {
        uint256[4] memory sizes = [uint256(1), 3, 7, 16];
        for (uint256 ed; ed < EDITIONS; ++ed) {
            uint256 seed = _seedFor(ed);
            for (uint256 k; k < sizes.length; ++k) {
                string memory svg = art.render(_card(seed, sizes[k], "NVDA", "Test Bundle", 42));
                bytes memory b = bytes(svg);
                assertGt(b.length, 800, "edition produced a near-empty card");
                assertTrue(_startsWith(svg, "<svg "), "missing svg root");
                assertTrue(_contains(svg, "</svg>"), "unterminated svg");
                assertTrue(_contains(svg, "NVDA"), "constituents must be legible on every edition");
            }
        }
    }

    /// Gradient and pattern ids are token-scoped. Marketplace galleries and the dApp's
    /// own grid put many cards in one DOM, where duplicate ids mean the first
    /// definition silently wins and later cards render another card's colours.
    function test_defsIdsAreTokenScoped() public view {
        uint256 seed = _seedFor(8); // Aurora is the edition that defines gradients
        string memory a = art.render(_card(seed, 3, "NVDA", "Test Bundle", 1));
        string memory b = art.render(_card(seed, 3, "NVDA", "Test Bundle", 2));
        assertTrue(_contains(a, "id='a1'"), "card 1 must scope its gradient id");
        assertTrue(_contains(b, "id='a2'"), "card 2 must scope its gradient id");
        assertFalse(_contains(b, "id='a1'"), "ids must not collide across cards");
    }

    /// A preview and the minted card must be the same artwork: every trait derives from
    /// (name, creator) and never from tokenId.
    function test_previewMatchesMintedArt() public view {
        uint256 seed = _seedFor(1);
        ICardArt.Card memory minted = _card(seed, 4, "NVDA", "Test Bundle", 77);
        ICardArt.Card memory preview = _card(seed, 4, "NVDA", "Test Bundle", 0);
        preview.preview = true;
        (uint256 e1, uint256 p1, uint256 f1) = art.traits(minted.seed);
        (uint256 e2, uint256 p2, uint256 f2) = art.traits(preview.seed);
        assertEq(e1, e2);
        assertEq(p1, p2);
        assertEq(f1, f2);
        assertTrue(_contains(art.render(preview), "PREVIEW"), "preview must be marked unsealed");
        assertFalse(_contains(art.render(minted), "PREVIEW"), "minted card must not read as a preview");
    }

    /// A 31-character name (the contract's maximum) must be scaled to its column
    /// rather than allowed to run off the card and collide with the serial. Strata is
    /// the tightest case: it sets the name on the same line as the serial. On the wide
    /// Ledger plate the same name now fits at full size — that is correct, not a
    /// regression, and is why this test targets the narrow column specifically.
    function test_longNameIsScaledToFit() public view {
        uint256 seed = _seedFor(1);
        string memory long_ = "abcdefghijklmnopqrstuvwxyzabcde";
        uint256 bigSize = _fontSizeOf(art.render(_card(seed, 3, "NVDA", "Short", 1)), "Short");
        uint256 smallSize = _fontSizeOf(art.render(_card(seed, 3, "NVDA", long_, 1)), long_);
        assertEq(bigSize, 22, "a short name uses the full display size");
        assertLt(smallSize, bigSize, "a 31-char name must be scaled down in a tight column");
        // the whole point: the scaled name has to actually fit the column it sits in
        assertLt(smallSize * bytes(long_).length * 55 / 100, 340, "scaled name still overflows its column");
    }

    /// The canvas is 1:1. Wallets and marketplaces render an NFT into a square box, so
    /// a portrait card gets letterboxed or cover-cropped (MetaMask crops the header).
    function test_canvasIsSquare() public view {
        string memory svg = art.render(_card(_seedFor(0), 3, "NVDA", "Test Bundle", 1));
        assertTrue(_contains(svg, "viewBox='0 0 500 500'"), "viewBox must be square");
        assertTrue(_contains(svg, "width='1000' height='1000'"), "intrinsic size must be square and >=350px");
    }

    /// Orbit draws each position inside a ~40px circle: an 11-character ticker has to
    /// be clipped, not merely scaled, or it runs clean outside the node.
    function test_orbitClipsNodeLabels() public view {
        string memory svg = art.render(_card(_seedFor(5), 6, "mLONGSYMBOL", "Test Bundle", 1));
        assertFalse(_contains(svg, "mLONGSYMBOL"), "an 11-char ticker must not be drawn whole in a node");
        assertTrue(_contains(svg, "mLONG"), "the clipped prefix must still identify the position");
    }

    /// The basket is never silently truncated. Every edition caps how much it draws,
    /// so every edition must say so — either by naming the remainder ("+6 more") or by
    /// stating the true total. Tape draws a ticker rather than a row list and takes the
    /// second route; without this it rendered a 16-position basket identically to a 3.
    function test_overflowIsDisclosed() public view {
        for (uint256 ed; ed < EDITIONS; ++ed) {
            string memory svg = art.render(_card(_seedFor(ed), 16, "NVDA", "Test Bundle", 1));
            bool namesRemainder = _contains(svg, " more") || _contains(svg, " MORE");
            bool statesTotal = _contains(svg, "16 POS") || _contains(svg, "16 POSITIONS");
            assertTrue(namesRemainder || statesTotal, "a capped card must disclose what it omits");
        }
    }

    function test_traitNamesCoverEveryIndex() public view {
        for (uint256 e; e < EDITIONS; ++e) {
            for (uint256 p; p < 12; ++p) {
                for (uint256 f; f < 5; ++f) {
                    (string memory en, string memory pn, string memory fn, string memory tn) = art.traitNames(e, p, f);
                    assertGt(bytes(en).length, 0);
                    assertGt(bytes(pn).length, 0);
                    assertGt(bytes(fn).length, 0);
                    assertGt(bytes(tn).length, 0, "every combination must resolve to a tier");
                }
            }
        }
    }

    /// Rarity has to be monotone: the scarcest edition on a rare palette with the
    /// scarcest finish must outrank the house style on a common palette, or the Tier
    /// badge is decoration rather than information.
    function test_tierTracksScarcity() public view {
        (,,, string memory plainest) = art.traitNames(0, 0, 0); // Ledger / Obsidian / Matte
        (,,, string memory richest) = art.traitNames(9, 8, 4); // Guilloche / Gilt / Prismatic
        assertEq(plainest, "Common");
        assertEq(richest, "Mythic");
        (,,, string memory middling) = art.traitNames(3, 0, 2); // Mosaic / common / Foil
        assertEq(middling, "Uncommon");
    }

    /// Every edition index the weighting can produce must be reachable from some seed.
    /// A gap here means a composition that exists in the bytecode but can never mint.
    function test_everyEditionIsReachable() public view {
        bool[EDITIONS] memory seen;
        for (uint256 s = 1; s < 6000; ++s) {
            (uint256 ed,,) = art.traits(uint256(keccak256(abi.encodePacked(s))));
            seen[ed] = true;
        }
        for (uint256 e; e < EDITIONS; ++e) {
            assertTrue(seen[e], "edition unreachable from any seed");
        }
    }

    function testFuzz_neverRevertsOnAnySeed(uint256 seed, uint8 rawN) public view {
        uint256 n = uint256(rawN) % 17;
        string memory svg = art.render(_card(seed, n, "NVDA", "Fuzzed Bundle", 1));
        assertTrue(_contains(svg, "</svg>"), "must terminate for any seed and basket size");
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || h.length < n.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool hit = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) return true;
        }
        return false;
    }

    /// @dev font-size of the `<text>` element whose body is exactly `body`. Needed
    ///      because several elements share a size — asserting on `font-size='22'`
    ///      anywhere in the document matched the serial, not the name under test.
    function _fontSizeOf(string memory svg, string memory body) internal pure returns (uint256) {
        bytes memory h = bytes(svg);
        bytes memory needle = bytes(string.concat(">", body, "</text>"));
        for (uint256 i; i + needle.length <= h.length; ++i) {
            bool hit = true;
            for (uint256 j; j < needle.length; ++j) {
                if (h[i + j] != needle[j]) {
                    hit = false;
                    break;
                }
            }
            if (!hit) continue;
            // scan back to this element's font-size='N'
            bytes memory fs = bytes("font-size='");
            for (uint256 k = i; k > fs.length; --k) {
                bool m = true;
                for (uint256 j; j < fs.length; ++j) {
                    if (h[k - fs.length + j] != fs[j]) {
                        m = false;
                        break;
                    }
                }
                if (!m) continue;
                uint256 v;
                for (uint256 q = k; q < h.length && h[q] != "'"; ++q) {
                    v = v * 10 + (uint8(h[q]) - 48);
                }
                return v;
            }
        }
        revert("text element not found");
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory p = bytes(prefix);
        if (b.length < p.length) return false;
        for (uint256 i; i < p.length; ++i) {
            if (b[i] != p[i]) return false;
        }
        return true;
    }
}
