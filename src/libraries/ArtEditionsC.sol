// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICardArt} from "../interfaces/ICardArt.sol";
import {ArtCommon} from "./ArtCommon.sol";
import {ArtSVG} from "./ArtSVG.sol";

/// @title ArtEditionsC — card compositions, set C. Linked library.
/// @dev   A third split, forced by EIP-170: turning Orbit into a real orrery (two
///        counter-rotating rings, each node counter-rotated so its ticker stays
///        upright) pushed ArtEditions 326 bytes past the 24,576-byte ceiling. Orbit
///        is the most geometry-heavy edition, so it moved out on its own and set C
///        now has room for whatever comes next.
library ArtEditionsC {
    using Strings for uint256;

    /// @dev ORBIT — positions as satellites around the card itself: the same picture
    ///      the dApp draws for pack(), turned into the artwork. The 60-tick dial keeps
    ///      a one-position basket from reading as an empty field.
    function _orbit(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 10 ? 10 : c.symbols.length;
        int256 cx = 250;
        int256 cy = 248;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            ArtCommon._frame(p),
            ArtCommon._eyebrow(250, 48, p, 2),
            ArtSVG.txt(250, 78, ArtCommon._nameSize(440, bytes(c.name).length), 1 | 2 | 16, 0, p.ink, 100, c.name),
            ArtSVG.circle(cx, cy, n <= 2 ? 96 : 84, "none", p.dim, 25),
            ArtSVG.circle(cx, cy, 138, "none", p.dim, 18)
        );
        // Two paths rather than sixty `<line>` tags: identical geometry, ~3.7KB less.
        string memory major;
        string memory minor;
        for (uint256 k; k < 60; ++k) {
            int256 a = int256(k) * 6 - 90;
            bool isMajor = k % 5 == 0;
            int256 r2 = isMajor ? int256(150) : int256(155);
            string memory sg = ArtSVG.seg(
                cx + r2 * ArtCommon._cos(a) / 10000,
                cy + r2 * ArtCommon._sin(a) / 10000,
                cx + int256(160) * ArtCommon._cos(a) / 10000,
                cy + int256(160) * ArtCommon._sin(a) / 10000
            );
            if (isMajor) major = string.concat(major, sg);
            else minor = string.concat(minor, sg);
        }
        o = string.concat(o, "<g class='dl'>", ArtSVG.path(minor, p.dim, 20), ArtSVG.path(major, p.dim, 45), "</g>");

        o = string.concat(o, _orbitNodes(c, p, n));
        return string.concat(
            o,
            ArtCommon._compBar(p, 24, 424, 452, c.total > 16 ? 16 : c.total),
            ArtSVG.txt(24, 446, 8, 0, 18, p.dim, 100, string.concat(c.total.toString(), " POSITIONS")),
            ArtSVG.txt(476, 446, 8, 4, 18, p.acc, 100, "100% BACKED"),
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    function _orbitNodes(ICardArt.Card memory c, ArtCommon.P memory p, uint256 n)
        internal
        pure
        returns (string memory)
    {
        uint256 inner = n > 6 ? (n + 1) / 2 : n;
        // Two rings, two groups, two rates — one <g> per ring is what lets the outer
        // one run backwards. Drawn separately rather than in a single pass because a
        // single group can only carry a single rotation.
        return string.concat(
            "<g class='oi'>",
            _ring(c, p, 0, inner, inner, n <= 2 ? int256(96) : int256(84), n > 7 ? 20 : n > 4 ? 23 : 26, false),
            "</g><g class='oo'>",
            _ring(c, p, inner, n, n - inner, 138, n > 7 ? 20 : n > 4 ? 23 : 26, true),
            "</g>",
            // the core is the one fixed point: everything else turns around it
            ArtSVG.circle(250, 248, 38, p.acc, "", 0),
            ArtSVG.txt(
                250, 254, 19, 1 | 2 | 16, 0, p.light ? "#FFFFFF" : p.bg0, 100, c.preview ? "-" : ArtCommon._serial(c)
            )
        );
    }

    /// @dev One ring of satellites plus its spokes. Each node is translated into place
    ///      and its contents wrapped in a counter-rotating group running at exactly the
    ///      ring's period, so the tickers stay upright while the ring turns — without
    ///      that, every label is upside down within half a revolution.
    function _ring(
        ICardArt.Card memory c,
        ArtCommon.P memory p,
        uint256 from,
        uint256 to,
        uint256 cnt,
        int256 r,
        uint256 nodeR,
        bool outer
    ) private pure returns (string memory) {
        if (cnt == 0 || from >= to) return "";
        int256 cx = 250;
        int256 cy = 248;
        int256 rot = int256(ArtCommon._sb(c.seed, 7) % 60) - 30;
        string memory spokes;
        string memory nodes;

        for (uint256 i = from; i < to; ++i) {
            uint256 k = i - from;
            int256 deg = int256(360 * k / cnt) + rot + (outer ? int256(180 / cnt) : int256(0)) - 90;
            int256 nx = cx + r * ArtCommon._cos(deg) / 10000;
            int256 ny = cy + r * ArtCommon._sin(deg) / 10000;
            spokes = string.concat(spokes, ArtSVG.seg(cx, cy, nx, ny));
            nodes = string.concat(
                nodes,
                "<g transform='translate(",
                ArtSVG.itoa(nx),
                ",",
                ArtSVG.itoa(ny),
                ")'><g class='",
                outer ? "co" : "ci",
                "'>",
                ArtSVG.circle(0, 0, nodeR, p.bg1, p.ink, 70),
                // a node is 38-48px across: an 11-character ticker has to be clipped,
                // not merely scaled, or it runs clean out of the circle
                ArtSVG.txt(0, 0, nodeR > 20 ? 8 : 7, 2 | 8, 0, p.ink, 100, ArtCommon._trunc(c.symbols[i], 5)),
                ArtSVG.txt(0, 11, 6, 2, 0, p.dim, 100, ArtCommon._trunc(c.amountStrs[i], 8)),
                "</g></g>"
            );
        }
        return string.concat(ArtSVG.path(spokes, p.dim, 45), nodes);
    }
}
