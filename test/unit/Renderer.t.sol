// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {StockPackTestBase} from "../utils/TestBase.sol";
import {SVGCard} from "../../src/libraries/SVGCard.sol";
import {MockStockToken} from "../../src/mocks/MockStockToken.sol";
import {BaseMockERC20} from "../mocks/WeirdTokens.sol";
import {IStockPackRenderer} from "../../src/interfaces/IStockPackRenderer.sol";
import {StockPackRenderer} from "../../src/StockPackRenderer.sol";

/// @dev symbol() reverts entirely (standalone: `symbol` is a state var in the base mock).
contract RevertingSymbolToken {
    string public name = "Broken";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function symbol() public pure returns (string memory) {
        revert("nope");
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev 10KB symbol — must degrade to the hex fallback or truncate, never brick tokenURI.
contract HugeSymbolToken is BaseMockERC20 {
    constructor() BaseMockERC20("Huge", "") {
        bytes memory b = new bytes(10_000);
        for (uint256 i; i < b.length; ++i) {
            b[i] = "A";
        }
        symbol = string(b);
    }
}

/// @dev Injection attempt through symbol().
contract InjectionSymbolToken is BaseMockERC20 {
    constructor() BaseMockERC20("Evil", '"><script>alert(1)</script>') {}
}

contract RendererTest is StockPackTestBase {
    function _mintBundle(string memory name) internal returns (uint256 id) {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        vm.prank(alice);
        id = pack.pack(name, tokens, amounts);
    }

    function test_tokenURI_decodes_validJSON_withTraits() public {
        uint256 id = _mintBundle("The Big Tech Bundle");
        string memory uri = pack.tokenURI(id);
        assertTrue(contains(uri, "data:application/json;base64,"));

        string memory json = decodeDataURI(uri);
        // vm.parseJson* revert on malformed JSON — parsing IS the validity check
        assertEq(vm.parseJsonString(json, "$.name"), unicode"The Big Tech Bundle · StockPack #1");
        string memory image = vm.parseJsonString(json, "$.image");
        assertTrue(contains(image, "data:image/svg+xml;base64,"));

        string memory svg = decodeDataURI(image);
        assertTrue(contains(svg, "<svg"));
        assertTrue(contains(svg, "mNVDA"));
        assertTrue(contains(svg, "mAAPL"));
        assertTrue(contains(svg, "The Big Tech Bundle"));
        assertTrue(contains(svg, "100% REDEEMABLE"));

        // per-symbol trait attributes present
        assertTrue(contains(json, '"trait_type":"mNVDA"'));
        assertTrue(contains(json, '"trait_type":"Stocks","value":3'));
        assertTrue(contains(json, '"trait_type":"Bundle Name"'));
    }

    function test_tokenURI_sizeBudget() public {
        // worst case: 16 tokens, long symbols, max-length name
        address[] memory tokens = new address[](16);
        uint256[] memory amounts = new uint256[](16);
        for (uint256 i; i < 16; ++i) {
            MockStockToken t = new MockStockToken("Mock Stock Token Long", "mLONGSYMBOL", 18);
            tokens[i] = address(t);
            amounts[i] = 123_456_789e10;
        }
        sortBasket(tokens, amounts);
        fund(alice, tokens, amounts);
        vm.prank(alice);
        uint256 id = pack.pack("abcdefghijklmnopqrstuvwxyzabcde", tokens, amounts);

        uint256 gasBefore = gasleft();
        string memory uri = pack.tokenURI(id);
        uint256 uriGas = gasBefore - gasleft();
        // tokenURI is served over eth_call, which nodes gas-cap (commonly 50M). The art
        // reaches its primitives through linked libraries, so each element costs a
        // DELEGATECALL; measured 2.36M at this worst case. Guard the order of magnitude.
        assertLt(uriGas, 10_000_000, "tokenURI must stay well inside a node's eth_call cap");
        // Budget raised deliberately from 8KB/4KB when the single fixed layout was
        // replaced by six generative editions. Measured worst case (this basket: 16
        // positions, 11-char symbols, 31-char name) is 15,545 bytes of tokenURI over
        // 8,154 bytes of SVG — see script/RenderSamples for the per-edition table.
        // Still bounded and still enforced, with enough headroom that a new edition
        // has room to exist but a runaway one fails here.
        assertLt(bytes(uri).length, 20480, "payload must stay under the 20KB budget");
        string memory svg = decodeDataURI(vm.parseJsonString(decodeDataURI(uri), "$.image"));
        // Raised again when per-edition animation was added: measured worst case is
        // now 9,928 bytes, and a cap 3% above the measurement is a tripwire rather
        // than a budget. 12KB still catches a runaway edition.
        assertLt(bytes(svg).length, 12288, "raw SVG must stay under 12KB");
        // Every edition caps its rows; the overflow marker proves the basket is not
        // silently truncated. Tape has no row list, so it is exempt.
        assertTrue(contains(svg, " more") || contains(svg, "16 POS"), "overflow must be disclosed");
    }

    function test_tokenURI_hostileSymbols_neverBreakMetadata() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(new RevertingSymbolToken());
        tokens[1] = address(new HugeSymbolToken());
        tokens[2] = address(new InjectionSymbolToken());
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e18;
        amounts[1] = 2e18;
        amounts[2] = 3e18;
        sortBasket(tokens, amounts);
        for (uint256 i; i < 3; ++i) {
            BaseMockERC20(tokens[i]).mint(alice, amounts[i]);
            vm.prank(alice);
            BaseMockERC20(tokens[i]).approve(address(pack), type(uint256).max);
        }
        vm.prank(alice);
        uint256 id = pack.pack("Hostile", tokens, amounts);

        string memory json = decodeDataURI(pack.tokenURI(id));
        vm.parseJsonString(json, "$.name"); // reverts if the JSON is broken
        string memory svg = decodeDataURI(vm.parseJsonString(json, "$.image"));
        assertFalse(contains(svg, "<script"), "raw script must never survive escaping");
        assertFalse(contains(json, "<script>"), "raw script must never survive escaping");
    }

    function test_tokenURI_hostileName_escaped() public {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        vm.prank(alice);
        uint256 id = pack.pack('x"><img src=x onerror=alert(1)>', tokens, amounts);

        string memory json = decodeDataURI(pack.tokenURI(id));
        vm.parseJsonString(json, "$.name");
        string memory svg = decodeDataURI(vm.parseJsonString(json, "$.image"));
        assertFalse(contains(svg, "<img"), "XML injection must be escaped in the SVG");
    }

    function test_previewSVG_parity_tokenIdIndependentLayers() public {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        string memory preview = renderer.previewSVG(tokens, amounts, "The Big Tech Bundle", alice);
        assertTrue(contains(preview, unicode"PREVIEW · UNSEALED"));

        vm.prank(alice);
        uint256 id = pack.pack("The Big Tech Bundle", tokens, amounts);
        string memory minted = decodeDataURI(vm.parseJsonString(decodeDataURI(pack.tokenURI(id)), "$.image"));

        // Same deterministic palette (derived from name+creator, never tokenId) and same rows.
        string memory paletteNeedle = _extractPaletteNeedle(minted);
        assertTrue(contains(preview, paletteNeedle), "palette must match between preview and minted card");
        assertTrue(contains(preview, "mNVDA") && contains(minted, "mNVDA"));
        assertTrue(contains(minted, unicode"SEALED") && !contains(minted, unicode"UNSEALED"));
    }

    function test_previewSVG_differentCreator_differentHue() public view {
        // hue depends on creator: two creators with the same name get distinct cards
        uint256 hueA = uint256(keccak256(abi.encodePacked("Same Name", alice))) % 360;
        uint256 hueB = uint256(keccak256(abi.encodePacked("Same Name", bob))) % 360;
        // sanity of the derivation used by the renderer (collision possible but not for these fixtures)
        assertTrue(hueA != hueB);
    }

    function test_formatAmount_dustHonesty() public pure {
        assertEq(SVGCard.formatAmount(1, 18), "<0.000001"); // 1 wei — below card precision
        assertEq(SVGCard.formatAmount(5e15, 18), "0.005"); // small share counts are first-class
        assertEq(SVGCard.formatAmount(52e14, 18), "0.0052");
        assertEq(SVGCard.formatAmount(9_999e12, 18), "0.009999");
        assertEq(SVGCard.formatAmount(123e12, 18), "0.000123");
        assertEq(SVGCard.formatAmount(1e12, 18), "0.000001"); // exactly card precision
        assertEq(SVGCard.formatAmount(999e9, 18), "<0.000001"); // just below — truncated, not rounded up
        assertEq(SVGCard.formatAmount(1e16, 18), "0.01");
        assertEq(SVGCard.formatAmount(1e18, 18), "1");
        assertEq(SVGCard.formatAmount(15e17, 18), "1.5");
        assertEq(SVGCard.formatAmount(1_234e15, 18), "1.23"); // truncated, not rounded
        assertEq(SVGCard.formatAmount(25e4, 6), "0.25");
        assertEq(SVGCard.formatAmount(5_000, 6), "0.005"); // 0.005 at 6 decimals
        assertEq(SVGCard.formatAmount(1, 6), "0.000001"); // 1 raw unit at 6 decimals
        assertEq(SVGCard.formatAmount(3, 4), "0.0003"); // dec < 6 dust path
        assertEq(SVGCard.formatAmount(42, 0), "42");
        // adversarial decimals: (amount % unit) * 100 used to overflow for dec >= 76
        assertEq(SVGCard.formatAmount(type(uint256).max, 77), "1.15");
    }

    function test_formatDate() public pure {
        assertEq(SVGCard.formatDate(0), "1970-01-01");
        assertEq(SVGCard.formatDate(1756684800), "2025-09-01");
        assertEq(SVGCard.formatDate(1788220800), "2026-09-01"); // 2026-09-01T00:00:00Z
        assertEq(SVGCard.formatDate(4102444800), "2100-01-01");
    }

    function test_contractURI_decodes() public view {
        string memory json = decodeDataURI(pack.contractURI());
        assertEq(vm.parseJsonString(json, "$.name"), "StockPack");
        assertTrue(contains(vm.parseJsonString(json, "$.image"), "data:image/svg+xml;base64,"));
    }

    /// @dev Pulls "hsl(<hue>," out of a rendered SVG to compare hue across renders.
    /// @dev First `fill='#rrggbb'` in the document — the card ground, and therefore a
    ///      direct read of which palette the seed selected. Replaces the old hsl() hue
    ///      probe: the art is palette-driven now, but the invariant under test (visual
    ///      identity depends on name+creator, never tokenId) is the same one.
    function _extractPaletteNeedle(string memory svg) private pure returns (string memory) {
        bytes memory b = bytes(svg);
        bytes memory prefix = "fill='#";
        for (uint256 i; i + 14 < b.length; ++i) {
            bool hit = true;
            for (uint256 j; j < prefix.length; ++j) {
                if (b[i + j] != prefix[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) {
                bytes memory out = new bytes(prefix.length + 6);
                for (uint256 k; k < out.length; ++k) {
                    out[k] = b[i + k];
                }
                return string(out);
            }
        }
        revert("palette fill not found");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // baseUrl — the renderer's only mutable state, artist-only, survives lockRenderer()
    // ─────────────────────────────────────────────────────────────────────────

    function test_baseUrl_seededAtConstruction_andEmbedded() public {
        assertEq(renderer.baseUrl(), "https://stock-pack.vercel.app");
        uint256 id = _mintBundle("Domain");
        string memory json = decodeDataURI(pack.tokenURI(id));
        assertEq(vm.parseJsonString(json, "$.external_url"), "https://stock-pack.vercel.app/bundle/1");
        assertTrue(contains(vm.parseJsonString(json, "$.description"), "App: https://stock-pack.vercel.app"));
    }

    function test_setBaseUrl_artistOnly_repointsExistingCards_evenAfterLock() public {
        uint256 id = _mintBundle("Domain");

        vm.prank(alice);
        vm.expectRevert(IStockPackRenderer.NotArtist.selector);
        renderer.setBaseUrl("https://stockpack.xyz");

        // locking the escrow's renderer pointer must not freeze the display origin
        vm.prank(artist);
        pack.lockRenderer();

        vm.expectEmit(false, false, false, true);
        emit IStockPackRenderer.BaseUrlUpdated("https://stockpack.xyz");
        vm.prank(artist);
        renderer.setBaseUrl("https://stockpack.xyz");

        assertEq(renderer.baseUrl(), "https://stockpack.xyz");
        string memory json = decodeDataURI(pack.tokenURI(id));
        assertEq(vm.parseJsonString(json, "$.external_url"), "https://stockpack.xyz/bundle/1");
        assertTrue(contains(vm.parseJsonString(json, "$.description"), "Unpack at https://stockpack.xyz/bundle/1)"));
    }

    function test_setBaseUrl_rejectsUnsafeOrMalformed() public {
        string[8] memory bad = [
            "http://stockpack.xyz", // not https
            "https://stockpack.xyz/", // trailing slash would double up in /bundle/
            "https://", // empty host
            "stockpack.xyz",
            'https://stockpack.xyz"', // JSON breakout
            "https://stockpack.xyz\\",
            "https://stock pack.xyz", // whitespace
            "https://stockpack.xyz<x>"
        ];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(artist);
            vm.expectRevert(IStockPackRenderer.InvalidBaseUrl.selector);
            renderer.setBaseUrl(bad[i]);
        }
        vm.expectRevert(IStockPackRenderer.InvalidBaseUrl.selector);
        new StockPackRenderer(address(pack), address(art), "http://nope");

        // over length
        bytes memory long = new bytes(201);
        for (uint256 i; i < long.length; ++i) {
            long[i] = "a";
        }
        long[0] = "h";
        long[1] = "t";
        long[2] = "t";
        long[3] = "p";
        long[4] = "s";
        long[5] = ":";
        long[6] = "/";
        long[7] = "/";
        vm.prank(artist);
        vm.expectRevert(IStockPackRenderer.InvalidBaseUrl.selector);
        renderer.setBaseUrl(string(long));
    }
}
