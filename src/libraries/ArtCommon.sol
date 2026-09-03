// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICardArt} from "../interfaces/ICardArt.sol";
import {ArtSVG} from "./ArtSVG.sol";
import {SVGCard} from "./SVGCard.sol";

/// @title ArtCommon — geometry, palette type and shared chrome for the card editions.
/// @dev   Everything here is `internal`, so it inlines into whichever edition library
///        uses it. That duplicates a few hundred bytes per library, which is the right
///        trade: a DELEGATECALL per clamp() would cost far more than it saves, and the
///        edition libraries are the ones that need the EIP-170 room.
library ArtCommon {
    using Strings for uint256;

    // over; the extra 150px of width is spent on the columns.
    uint256 internal constant W = 500;
    uint256 internal constant H = 500;

    ///      Orbit edition needs arbitrary angles: snapping to a coarse table makes a
    ///      7-node ring visibly uneven, so this is stored at 1° and reflected into the
    ///      other three quadrants.
    bytes private constant SIN = hex"000000af015d020b02ba0368041504c30570061c06c80774081f08ca09730a1c"
        hex"0ac40b6c0c120cb80d5c0e000ea20f430fe31082112011bc125712f01388141e"
        hex"14b3154615d8166816f61782180d1895191c19a11a231aa41b231b9f1c191c92"
        hex"1d071d7b1dec1e5b1ec81f321f9a2000206220c32120217c21d4222a227d22ce"
        hex"231c236723af23f52438247824b524ef2527255b258d25bb25e7261026352658"
        hex"2678269526af26c526d926ea26f82702270a270e2710";

    struct P {
        string bg0;
        string bg1;
        string ink;
        string dim;
        string acc;
        bool light;
    }

    function _clamp(uint256 v, uint256 lo, uint256 hi) internal pure returns (uint256) {
        return v < lo ? lo : v > hi ? hi : v;
    }

    /// @dev Byte `i` of the seed — the whole trait system reads from these.
    function _sb(uint256 seed, uint256 i) internal pure returns (uint256) {
        return (seed >> (8 * i)) & 0xff;
    }

    /// @dev Per-position entropy, so each constituent varies independently of the others.
    function _pb(uint256 seed, uint256 i, uint256 k) internal pure returns (uint256) {
        return _sb(uint256(keccak256(abi.encodePacked(seed, i))), k);
    }

    function _sin(int256 deg) internal pure returns (int256) {
        int256 d = deg % 360;
        if (d < 0) d += 360;
        uint256 u = uint256(d);
        if (u <= 90) return int256(_q(u));
        if (u <= 180) return int256(_q(180 - u));
        if (u <= 270) return -int256(_q(u - 180));
        return -int256(_q(360 - u));
    }

    function _cos(int256 deg) internal pure returns (int256) {
        return _sin(deg + 90);
    }

    function _q(uint256 d) internal pure returns (uint256) {
        return (uint256(uint8(SIN[2 * d])) << 8) | uint256(uint8(SIN[2 * d + 1]));
    }

    // ── Shared chrome ───────────────────────────────────────────────────────

    function _footerText(ICardArt.Card memory c) internal pure returns (string memory) {
        return c.preview
            ? unicode"PREVIEW · UNSEALED"
            : string.concat(
                "StockPack #",
                c.tokenId.toString(),
                unicode" · SEALED ",
                SVGCard.formatDate(c.sealedAt),
                unicode" · 100% REDEEMABLE"
            );
    }

    function _footer(ICardArt.Card memory c, string memory fill, uint256 op) internal pure returns (string memory) {
        return ArtSVG.txt(250, 477, 8, 2, 11, fill, op, _footerText(c));
    }

    /// @dev The inner keyline used by the editions that want a plate rather than a bleed.
    function _frame(P memory p) internal pure returns (string memory) {
        return string.concat(
            "<rect x='12' y='12' width='476' height='476' fill='none' stroke='", p.dim, "' stroke-opacity='0.4'/>"
        );
    }

    /// @dev SVG cannot measure text, so the name is fitted by character count. Names
    ///      are sanitized ASCII, so bytes == characters; the bold grotesque used for
    ///      display runs about 0.55em per character. `avail` is the px the name may use.
    function _nameSize(uint256 avail, uint256 len) internal pure returns (uint256) {
        if (len == 0) return 22;
        return _clamp(avail * 100 / (55 * len), 11, 22);
    }

    /// @dev Byte-safe truncation for the ASCII symbols/amounts that have to fit inside
    ///      a fixed shape (an Orbit node, say) rather than a free line.
    function _trunc(string memory v, uint256 maxLen) internal pure returns (string memory) {
        bytes memory b = bytes(v);
        if (b.length <= maxLen) return v;
        bytes memory out = new bytes(maxLen);
        for (uint256 i; i < maxLen; ++i) {
            out[i] = b[i];
        }
        return string(out);
    }

    function _two(uint256 v) internal pure returns (string memory) {
        return v < 10 ? string.concat("0", v.toString()) : v.toString();
    }

    function _eyebrow(int256 x, uint256 y, P memory p, uint256 flags) internal pure returns (string memory) {
        return ArtSVG.txt(x, y, 8, flags, 26, p.acc, 100, "STOCKPACK BUNDLE");
    }

    function _serial(ICardArt.Card memory c) internal pure returns (string memory) {
        return c.preview ? "#-" : string.concat("#", c.tokenId.toString());
    }

    /// @dev Segmented share-of-basket bar — the only chart on any card, and it plots
    ///      the one weighting the contract actually knows: position count.
    function _compBar(P memory p, uint256 x, uint256 y, uint256 w, uint256 n) internal pure returns (string memory o) {
        for (uint256 i; i < n; ++i) {
            uint256 sx = x + (i * w) / n;
            uint256 sw = w / n;
            o = string.concat(
                o,
                "<rect x='",
                sx.toString(),
                "' y='",
                y.toString(),
                "' width='",
                (sw > 2 ? sw - 2 : 1).toString(),
                "' height='5' fill='",
                i % 3 == 0 ? p.acc : p.dim,
                "' opacity='",
                i % 3 == 0 ? "1" : "0.5",
                "'/>"
            );
        }
    }

    /// @dev Etched is a hatch; Foil is two crisp diagonal sweeps rather than one broad
    ///      wash. Light palettes get a weaker, unblended sweep — screen-blending white
    ///      onto cream just bleaches the card and smears the type.

    /// @dev LEDGER — the house style. A bearer instrument: strict rules, a centred
    ///      watermark serial and positions as a ruled table. When the basket is sparse

    function _more(uint256 k) internal pure returns (string memory) {
        return string.concat("+", k.toString(), " more");
    }
}
