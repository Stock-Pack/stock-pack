// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICardArt} from "./interfaces/ICardArt.sol";
import {IStockPack} from "./interfaces/IStockPack.sol";
import {IStockPackRenderer} from "./interfaces/IStockPackRenderer.sol";
import {SVGCard} from "./libraries/SVGCard.sol";

/// @title StockPackRenderer — fully on-chain metadata for StockPack bundles.
/// @notice Separate descriptor contract (Uniswap-V3 pattern) so string-building bytecode
///         can never push the escrow core toward the EIP-170 limit. View surface: it
///         provably cannot touch escrow storage or move a token; its only mutable state
///         is the display-only `baseUrl` string.
/// @dev    Hardened against adversarial constituents: symbol()/decimals() are read via
///         raw staticcalls with manual return-data validation (no abi.decode bombs),
///         filtered to printable ASCII, truncated, then escaped for BOTH the JSON layer
///         (Strings.escapeJSON) and the SVG layer (SVGCard.escapeXML).
contract StockPackRenderer is IStockPackRenderer {
    using Strings for uint256;

    uint256 internal constant MAX_SYMBOL_CHARS = 11;

    uint256 internal constant MAX_BASE_URL_BYTES = 200;

    IStockPack public immutable stockPack;

    /// @notice The generative artwork contract. Immutable here and pure over there:
    ///         swapping art means swapping this renderer, which the escrow's `artist`
    ///         can do until lockRenderer() — and never after.
    ICardArt public immutable art;

    /// @notice dApp origin embedded in metadata (external_url + human-readable redeem hint),
    ///         e.g. "https://stock-pack.vercel.app" (no trailing slash).
    /// @dev    Storage, not a constant, so the escrow's `artist` can re-point every card at a
    ///         new domain without a renderer swap — and still can after lockRenderer(), which
    ///         only freezes the renderer *pointer*. Display-only: nothing here can touch funds.
    string public baseUrl;

    /// @param stockPack_ May be a not-yet-deployed, precomputed address: the deploy
    ///        script derives it via vm.computeCreateAddress and asserts after deploy.
    constructor(address stockPack_, address art_, string memory baseUrl_) {
        stockPack = IStockPack(stockPack_);
        art = ICardArt(art_);
        _setBaseUrl(baseUrl_);
    }

    /// @inheritdoc IStockPackRenderer
    function setBaseUrl(string calldata newBaseUrl) external {
        if (msg.sender != stockPack.artist()) revert NotArtist();
        _setBaseUrl(newBaseUrl);
    }

    /// @dev Must be an https origin with no trailing slash, ASCII-printable, and free of
    ///      `"` / `\` so it can be spliced verbatim into the JSON string fields.
    function _setBaseUrl(string memory newBaseUrl) private {
        bytes memory b = bytes(newBaseUrl);
        uint256 n = b.length;
        if (n < 9 || n > MAX_BASE_URL_BYTES || b[n - 1] == "/") revert InvalidBaseUrl();
        if (
            b[0] != "h" || b[1] != "t" || b[2] != "t" || b[3] != "p" || b[4] != "s" || b[5] != ":" || b[6] != "/"
                || b[7] != "/"
        ) revert InvalidBaseUrl();
        for (uint256 i = 8; i < n; ++i) {
            bytes1 c = b[i];
            if (c <= 0x20 || c >= 0x7F || c == '"' || c == "\\" || c == "<" || c == ">") revert InvalidBaseUrl();
        }
        baseUrl = newBaseUrl;
        emit BaseUrlUpdated(newBaseUrl);
    }

    /// @inheritdoc IStockPackRenderer
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        (address[] memory tokens, uint256[] memory amounts) = stockPack.getBasket(tokenId);
        (string memory rawName, address creator, uint64 sealedAt) = stockPack.bundleMeta(tokenId);
        string memory name = _sanitize(bytes(rawName), 31);
        (string[] memory syms, string[] memory amts) = _display(tokens, amounts);

        uint256 seed = _seed(name, creator);
        string memory svg = art.render(
            ICardArt.Card({
                name: SVGCard.escapeXML(name),
                tokenId: tokenId,
                sealedAt: sealedAt,
                symbols: _escapeAll(syms),
                amountStrs: _escapeAll(amts),
                total: tokens.length,
                seed: seed,
                preview: false
            })
        );

        return _wrapJSON(tokenId, name, sealedAt, svg, syms, amts, seed);
    }

    function _wrapJSON(
        uint256 tokenId,
        string memory name,
        uint64 sealedAt,
        string memory svg,
        string[] memory syms,
        string[] memory amts,
        uint256 seed
    ) private view returns (string memory) {
        string memory idStr = tokenId.toString();
        string memory bundleUrl = string.concat(baseUrl, "/bundle/", idStr);
        string memory description = string.concat(
            "Worth exactly ",
            _contents(syms, amts),
            " - a bearer claim redeemable 1:1. As the NFT holder you can burn this card via unpack() to withdraw those exact tokens to your wallet in one transaction (one-click Unpack at ",
            bundleUrl,
            "); redemption is owner-only, so marketplace approvals can never drain it. Amounts are raw token units, fixed at mint - verify on-chain with getBasket(",
            idStr,
            "). Tokenized stocks may accrue corporate-action value via their ERC-8056 uiMultiplier while escrowed. App: ",
            baseUrl
        );
        string memory head = string.concat(
            '{"name":"',
            Strings.escapeJSON(name),
            unicode" · StockPack #",
            idStr,
            '","description":"',
            description,
            '","external_url":"',
            bundleUrl,
            '"'
        );
        string memory json = string.concat(
            head,
            ',"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":',
            _attributes(syms, amts, name, sealedAt, syms.length, seed),
            "}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev Human-readable basket contents for the description, e.g. "12 mAMZN + 0.1 mMSFT".
    ///      Symbols are JSON-escaped; amounts are preformatted numeric strings.
    function _contents(string[] memory syms, string[] memory amts) private pure returns (string memory out) {
        for (uint256 i; i < syms.length; ++i) {
            string memory leg = string.concat(amts[i], " ", Strings.escapeJSON(syms[i]));
            out = i == 0 ? leg : string.concat(out, " + ", leg);
        }
    }

    /// @inheritdoc IStockPackRenderer
    function contractURI() external pure returns (string memory) {
        string memory logo =
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 350 350' width='350' height='350'><rect width='350' height='350' rx='24' fill='#0d1117'/><rect x='95' y='70' width='160' height='224' rx='14' fill='none' stroke='#e8b44f' stroke-width='3'/><rect x='115' y='102' width='120' height='10' rx='5' fill='#f5f2ea'/><rect x='115' y='138' width='90' height='8' rx='4' fill='#8f897d'/><rect x='115' y='162' width='104' height='8' rx='4' fill='#8f897d'/><rect x='115' y='186' width='76' height='8' rx='4' fill='#8f897d'/><text x='175' y='262' text-anchor='middle' font-family='ui-monospace,monospace' font-size='16' font-weight='700' fill='#e8b44f'>PACK</text></svg>";
        string memory json = string.concat(
            '{"name":"StockPack","description":"Basket-wrapper portfolio cards: each NFT escrows an exact basket of ERC-20 tokens, 100% backed and redeemable by the holder at any time by burning the card. No oracles, no fees, no fund-touching admin.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(logo)),
            '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @inheritdoc IStockPackRenderer
    function previewSVG(address[] calldata tokens, uint256[] calldata amounts, string calldata name, address creator)
        external
        view
        returns (string memory)
    {
        string memory clean = _sanitize(bytes(name), 31);
        (string[] memory syms, string[] memory amts) = _display(tokens, amounts);
        return art.render(
            ICardArt.Card({
                name: SVGCard.escapeXML(clean),
                tokenId: 0,
                sealedAt: 0,
                symbols: _escapeAll(syms),
                amountStrs: _escapeAll(amts),
                total: tokens.length,
                seed: _seed(clean, creator),
                preview: true
            })
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Every trait — edition, palette, finish, and each position's own variation —
    ///      derives from this one seed. Deliberately tokenId-independent so the pre-mint
    ///      preview is the exact card the mint produces.
    function _seed(string memory name, address creator) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(name, creator)));
    }

    /// @dev The art contract takes pre-escaped strings: escaping inside its text
    ///      primitive would inline the escape loop into ~50 call sites. Amounts need it
    ///      too — formatAmount emits "<0.000001" for dust.
    function _escapeAll(string[] memory in_) private pure returns (string[] memory out) {
        out = new string[](in_.length);
        for (uint256 i; i < in_.length; ++i) {
            out[i] = SVGCard.escapeXML(in_[i]);
        }
    }

    function _display(address[] memory tokens, uint256[] memory amounts)
        private
        view
        returns (string[] memory syms, string[] memory amts)
    {
        uint256 n = tokens.length;
        syms = new string[](n);
        amts = new string[](n);
        for (uint256 i; i < n; ++i) {
            syms[i] = _tokenSymbol(tokens[i]);
            amts[i] = SVGCard.formatAmount(i < amounts.length ? amounts[i] : 0, _tokenDecimals(tokens[i]));
        }
    }

    function _attributes(
        string[] memory syms,
        string[] memory amts,
        string memory name,
        uint64 sealedAt,
        uint256 total,
        uint256 seed
    ) private view returns (string memory out) {
        (uint256 ed, uint256 pal, uint256 fin) = art.traits(seed);
        (string memory edName, string memory palName, string memory finName, string memory tierName) =
            art.traitNames(ed, pal, fin);
        out = string.concat(
            '[{"trait_type":"Tier","value":"',
            tierName,
            '"},{"trait_type":"Edition","value":"',
            edName,
            '"},{"trait_type":"Palette","value":"',
            palName,
            '"},{"trait_type":"Finish","value":"',
            finName,
            '"},{"trait_type":"Stocks","value":',
            total.toString(),
            '},{"trait_type":"Bundle Name","value":"',
            Strings.escapeJSON(name),
            '"},{"trait_type":"Sealed","value":"',
            SVGCard.formatDate(sealedAt),
            '"}'
        );
        for (uint256 i; i < syms.length; ++i) {
            out = string.concat(out, ',{"trait_type":"', Strings.escapeJSON(syms[i]), '","value":"', amts[i], '"}');
        }
        out = string.concat(out, "]");
    }

    /// @dev Raw staticcall + manual return-data parsing: a malformed or malicious
    ///      symbol() (wrong offsets, absurd lengths, bytes32-style like MKR, reverts,
    ///      returnbombs) degrades to a short-hex fallback instead of bricking tokenURI.
    function _tokenSymbol(address token) private view returns (string memory) {
        (bool ok, bytes memory d) = token.staticcall(abi.encodeWithSignature("symbol()"));
        if (ok) {
            if (d.length == 32) {
                // bytes32-style symbol: trim at first zero byte
                uint256 len;
                bytes memory raw = new bytes(32);
                for (; len < 32; ++len) {
                    if (d[len] == 0) break;
                    raw[len] = d[len];
                }
                assembly ("memory-safe") {
                    mstore(raw, len)
                }
                string memory s = _sanitize(raw, MAX_SYMBOL_CHARS);
                if (bytes(s).length != 0) return s;
            } else if (d.length >= 64) {
                uint256 off;
                uint256 len;
                assembly ("memory-safe") {
                    off := mload(add(d, 32))
                    len := mload(add(d, 64))
                }
                if (off == 32 && len <= d.length - 64) {
                    bytes memory raw = new bytes(len);
                    for (uint256 i; i < len; ++i) {
                        raw[i] = d[64 + i];
                    }
                    string memory s = _sanitize(raw, MAX_SYMBOL_CHARS);
                    if (bytes(s).length != 0) return s;
                }
            }
        }
        return _shortHex(token);
    }

    /// @dev decimals() is display-only, never accounting. Absurd values clamp to 18.
    function _tokenDecimals(address token) private view returns (uint8) {
        (bool ok, bytes memory d) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (!ok || d.length < 32) return 18;
        uint256 v;
        assembly ("memory-safe") {
            v := mload(add(d, 32))
        }
        return v <= 77 ? uint8(v) : 18;
    }

    /// @dev Keeps printable ASCII (0x20–0x7E) only, truncated to maxLen — guarantees the
    ///      result is valid inside both JSON and XML after escaping, for arbitrary bytes.
    ///      `<` and `>` are dropped outright: they have no place in a ticker or bundle
    ///      name, and stripping them kills HTML-injection vectors even in consumers that
    ///      forget to escape JSON string values.
    function _sanitize(bytes memory b, uint256 maxLen) private pure returns (string memory) {
        bytes memory out = new bytes(b.length);
        uint256 o;
        for (uint256 i; i < b.length && o < maxLen; ++i) {
            bytes1 c = b[i];
            if (c >= 0x20 && c <= 0x7E && c != "<" && c != ">") {
                out[o] = c;
                ++o;
            }
        }
        assembly ("memory-safe") {
            mstore(out, o)
        }
        return string(out);
    }

    function _shortHex(address token) private pure returns (string memory) {
        bytes16 hexChars = "0123456789abcdef";
        bytes20 a = bytes20(token);
        bytes memory out = new bytes(8);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i; i < 3; ++i) {
            out[2 + i * 2] = hexChars[uint8(a[i]) >> 4];
            out[3 + i * 2] = hexChars[uint8(a[i]) & 0x0f];
        }
        return string(out);
    }
}
