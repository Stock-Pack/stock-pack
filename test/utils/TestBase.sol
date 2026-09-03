// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {StockPack} from "../../src/StockPack.sol";
import {StockPackArt} from "../../src/art/StockPackArt.sol";
import {StockPackRenderer} from "../../src/StockPackRenderer.sol";
import {MockStockToken} from "../../src/mocks/MockStockToken.sol";

/// @notice Shared fixture: protocol deployed with the production bootstrap pattern
///         (renderer bound to the precomputed StockPack address), demo tokens, actors.
abstract contract StockPackTestBase is Test {
    StockPack internal pack;
    StockPackRenderer internal renderer;

    MockStockToken internal nvda;
    MockStockToken internal aapl;
    MockStockToken internal msft;
    MockStockToken internal tsla;

    StockPackArt internal art;
    address internal artist;
    address internal alice;
    uint256 internal aliceKey;
    address internal bob;

    function setUp() public virtual {
        artist = makeAddr("artist");
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");

        // Production bootstrap: renderer is deployed first, bound to the precomputed
        // escrow address; the escrow constructor then verifies renderer code exists.
        art = new StockPackArt();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        renderer = new StockPackRenderer(predicted, address(art), "https://stock-pack.vercel.app");
        pack = new StockPack(address(renderer), artist);
        assertEq(address(pack), predicted, "bootstrap address prediction failed");

        nvda = new MockStockToken("Mock NVIDIA", "mNVDA", 18);
        aapl = new MockStockToken("Mock Apple", "mAAPL", 18);
        msft = new MockStockToken("Mock Microsoft", "mMSFT", 18);
        tsla = new MockStockToken("Mock Tesla", "mTSLA", 6);
    }

    /// @dev Mints `amounts` of each token to `who` and max-approves the escrow.
    function fund(address who, address[] memory tokens, uint256[] memory amounts) internal {
        for (uint256 i; i < tokens.length; ++i) {
            MockStockToken(tokens[i]).mint(who, amounts[i]);
            vm.prank(who);
            MockStockToken(tokens[i]).approve(address(pack), type(uint256).max);
        }
    }

    /// @dev Canonical 3-token basket (sorted, funded for alice): 1 mNVDA + 2 mAAPL + 0.5 mMSFT.
    function bigTechBasket() internal returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](3);
        tokens[0] = address(nvda);
        tokens[1] = address(aapl);
        tokens[2] = address(msft);
        amounts = new uint256[](3);
        amounts[0] = 1e18;
        amounts[1] = 2e18;
        amounts[2] = 5e17;
        sortBasket(tokens, amounts);
        fund(alice, tokens, amounts);
    }

    /// @dev In-place insertion sort by token address (baskets must be strictly ascending).
    function sortBasket(address[] memory tokens, uint256[] memory amounts) internal pure {
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

    function contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return n.length == 0;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    /// @dev Standard base64 decoder (no padding tolerance needed — OZ always pads).
    function b64decode(string memory s) internal pure returns (bytes memory) {
        bytes memory data = bytes(s);
        require(data.length % 4 == 0, "b64: length");
        if (data.length == 0) return "";
        uint256 padding;
        if (data[data.length - 1] == "=") padding = data[data.length - 2] == "=" ? 2 : 1;
        bytes memory out = new bytes(data.length / 4 * 3 - padding);
        uint256 o;
        for (uint256 i; i < data.length; i += 4) {
            uint256 chunk = (_b64val(data[i]) << 18) | (_b64val(data[i + 1]) << 12) | (_b64val(data[i + 2]) << 6)
                | _b64val(data[i + 3]);
            if (o < out.length) out[o++] = bytes1(uint8(chunk >> 16));
            if (o < out.length) out[o++] = bytes1(uint8(chunk >> 8));
            if (o < out.length) out[o++] = bytes1(uint8(chunk));
        }
        return out;
    }

    function _b64val(bytes1 c) private pure returns (uint256) {
        uint8 v = uint8(c);
        if (v >= 65 && v <= 90) return v - 65; // A-Z
        if (v >= 97 && v <= 122) return v - 71; // a-z
        if (v >= 48 && v <= 57) return v + 4; // 0-9
        if (c == "+") return 62;
        if (c == "/") return 63;
        if (c == "=") return 0;
        revert("b64: char");
    }

    /// @dev Strips a "data:...;base64," prefix and decodes the payload.
    function decodeDataURI(string memory uri) internal pure returns (string memory) {
        bytes memory b = bytes(uri);
        uint256 start;
        for (uint256 i; i < b.length; ++i) {
            if (b[i] == ",") {
                start = i + 1;
                break;
            }
        }
        require(start != 0, "not a data uri");
        bytes memory payload = new bytes(b.length - start);
        for (uint256 i; i < payload.length; ++i) {
            payload[i] = b[start + i];
        }
        return string(b64decode(string(payload)));
    }
}
