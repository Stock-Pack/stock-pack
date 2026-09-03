// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICardArt} from "../interfaces/ICardArt.sol";
import {ArtCommon} from "./ArtCommon.sol";
import {ArtSVG} from "./ArtSVG.sol";

/// @title ArtEditions — card compositions, set A. Linked library.
/// @dev   Entry points are `public` so they live in this library's own bytecode rather
///        than inlining into StockPackArt, which would blow EIP-170. Set B lives in
///        ArtEditionsB; the split exists purely for the 24,576-byte ceiling.
///
///        Governing design rule for every edition, here and in B: it must compose at
///        n=1 and at n=16. Type scale, row pitch and band height are functions of the
///        constituent count, never constants — a layout tuned only for a mid-sized
///        basket degenerates into a flat coloured rectangle at one position.
library ArtEditions {
    using Strings for uint256;

    ///      the rows switch to display scale rather than trailing off into blank card.
    function _ledger(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 10 ? 10 : c.symbols.length;
        uint256 span = 424 - 152;
        uint256 step = n == 0 ? 92 : ArtCommon._clamp(span / n, 26, 92);
        // A one- or two-row block is shorter than the plate, so drop it toward centre.
        // The offset is capped: fully centred, a single row floated so far from the
        // POSITION/ESCROWED headers that the table stopped reading as one object.
        uint256 slack = n * step < span ? (span - n * step) / 2 : 0;
        uint256 top = 152 + (slack > 56 ? 56 : slack);
        uint256 fs = ArtCommon._clamp(step * 42 / 100, 12, 20);
        bool wide = step > 62;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            ArtCommon._frame(p),
            // paper-strength watermark, behind everything: anchored bottom-right at full
            // strength it fought the last rows of a large basket instead of sitting under them
            "<g class='wm'>",
            ArtSVG.txt(250, 322, 150, 1 | 2 | 32, 0, p.ink, 5, ArtCommon._serial(c)),
            "</g>",
            ArtCommon._eyebrow(28, 48, p, 0),
            ArtSVG.txt(464, 48, 8, 4, 26, p.dim, 100, string.concat(c.total.toString(), " POS")),
            ArtSVG.txt(28, 94, ArtCommon._nameSize(436, bytes(c.name).length), 1 | 16, 0, p.ink, 100, c.name),
            ArtSVG.line(28, 116, 464, 116, p.ink, 55),
            // the read head: full width, two pixels tall, running the table
            "<g class='sc'>",
            ArtSVG.rect(28, 145, 436, 10, p.acc),
            "</g>",
            ArtSVG.txt(28, 134, 8, 0, 18, p.dim, 100, "POSITION"),
            ArtSVG.txt(464, 134, 8, 4, 18, p.dim, 100, "ESCROWED")
        );

        for (uint256 i; i < n; ++i) {
            uint256 y = top + i * step;
            o = string.concat(
                o,
                wide
                    ? string.concat(
                        ArtSVG.txt(
                            28, y, ArtCommon._clamp(step * 30 / 100, 22, 40), 1 | 32, 0, p.ink, 100, c.symbols[i]
                        ),
                        ArtSVG.txt(
                                28,
                                y + ArtCommon._clamp(step * 26 / 100, 20, 30),
                                ArtCommon._clamp(step * 15 / 100, 12, 18),
                                0,
                                0,
                                p.dim,
                                100,
                                c.amountStrs[i]
                            ),
                        ArtSVG.txt(464, y, 11, 4, 14, p.acc, 100, ArtCommon._two(i + 1))
                    )
                    : string.concat(
                        ArtSVG.txt(28, y, fs, 8, 0, p.ink, 100, c.symbols[i]),
                        ArtSVG.txt(464, y, fs * 88 / 100, 4, 0, p.dim, 100, c.amountStrs[i])
                    ),
                ArtSVG.line(28, y + step * 36 / 100, 464, y + step * 36 / 100, p.dim, 22)
            );
        }
        if (c.total > n) {
            o = string.concat(o, ArtSVG.txt(28, top + n * step, 11, 0, 0, p.dim, 100, ArtCommon._more(c.total - n)));
        }

        return string.concat(
            o,
            ArtCommon._compBar(p, 28, 432, 436, c.total > 16 ? 16 : c.total),
            ArtSVG.txt(28, 452, 8, 0, 16, p.acc, 100, unicode"REDEEMABLE 1:1 · NO ORACLE · NO FEE"),
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    /// @dev STRATA — the basket as geology. One band per position, height driven by
    ///      that position's own hash, so the silhouette is a fingerprint of the actual
    ///      basket. Type grows into the band: a one-position card becomes a poster.
    function _strata(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 9 ? 9 : c.symbols.length;
        uint256 top = 116;
        uint256 bot = 450;

        uint256 sum;
        uint256[] memory wts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            wts[i] = 52 + ArtCommon._pb(c.seed, i, 0) % 70;
            sum += wts[i];
        }
        uint256 accIdx = n == 0 ? 0 : ArtCommon._sb(c.seed, 5) % n;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            ArtCommon._eyebrow(24, 46, p, 0),
            ArtSVG.txt(24, 86, ArtCommon._nameSize(340, bytes(c.name).length), 1 | 16, 0, p.ink, 100, c.name),
            ArtSVG.txt(476, 86, 22, 1 | 4 | 16, 0, p.dim, 100, ArtCommon._serial(c))
        );

        uint256 y = top;
        for (uint256 i; i < n && y < bot; ++i) {
            uint256 hh = i == n - 1 ? bot - y : ArtCommon._clamp(wts[i] * (bot - top) / sum, 26, bot - y);
            bool isAcc = i == accIdx;
            string memory fg = isAcc ? (p.light ? "#FFFFFF" : p.bg0) : p.ink;
            o = string.concat(
                o,
                isAcc ? "<g class='bd'>" : "",
                ArtSVG.rect(24, y, 452, hh, isAcc ? p.acc : (i % 2 == 1 ? p.bg1 : p.bg0)),
                isAcc ? "</g>" : ""
            );
            // hairline ruling gives a band an actual surface instead of dead colour
            if (hh > 44) {
                for (uint256 g = y + 14; g + 8 < y + hh; g += 13) {
                    o = string.concat(o, ArtSVG.line(24, g, 476, g, fg, 7));
                }
            }
            if (!isAcc) o = string.concat(o, ArtSVG.line(24, y, 476, y, p.dim, 32));
            o = string.concat(o, _strataRow(c, p, i, y, hh, fg));
            y += hh;
        }

        return string.concat(
            o,
            "<rect x='24' y='116' width='452' height='334' fill='none' stroke='",
            p.ink,
            "' stroke-opacity='0.5'/>",
            c.total > n ? ArtSVG.txt(24, 462, 8, 0, 10, p.dim, 100, ArtCommon._more(c.total - n)) : "",
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    /// @dev Split out of _strata purely to keep that function under the stack limit.
    function _strataRow(
        ICardArt.Card memory c,
        ArtCommon.P memory p,
        uint256 i,
        uint256 y,
        uint256 hh,
        string memory fg
    ) private pure returns (string memory) {
        uint256 cy = y + hh / 2;
        if (hh >= 200) {
            // A single position owns almost the whole plate. Left as one big symbol on
            // colour it reads as a swatch, so it gets a real composition: rule, labels
            // and the amount at its own scale.
            return string.concat(
                ArtSVG.txt(38, cy - 26, 64, 1 | 32, 0, fg, 100, c.symbols[i]),
                ArtSVG.line(38, cy - 8, 462, cy - 8, fg, 35),
                ArtSVG.txt(38, cy + 22, 9, 0, 18, fg, 65, "ESCROWED"),
                ArtSVG.txt(38, cy + 52, 30, 0, 0, fg, 90, c.amountStrs[i]),
                ArtSVG.txt(462, y + 26, 11, 4, 14, fg, 60, ArtCommon._two(i + 1))
            );
        }
        if (hh >= 130) {
            // one or two positions: symbol over amount, both at poster scale
            return string.concat(
                ArtSVG.txt(38, cy - 6, 46, 1 | 32, 0, fg, 100, c.symbols[i]),
                ArtSVG.txt(38, cy + 30, 20, 0, 0, fg, 75, c.amountStrs[i]),
                ArtSVG.txt(462, y + 24, 11, 4, 14, fg, 60, ArtCommon._two(i + 1))
            );
        }
        if (hh >= 74) {
            uint256 fs = ArtCommon._clamp(hh * 44 / 100, 13, 46);
            return string.concat(
                ArtSVG.txt(38, cy + fs * 18 / 100, fs, 1 | 32, 0, fg, 100, c.symbols[i]),
                ArtSVG.txt(
                    462, cy + fs * 18 / 100, ArtCommon._clamp(fs * 34 / 100, 11, 17), 4, 0, fg, 75, c.amountStrs[i]
                )
            );
        }
        return string.concat(
            ArtSVG.txt(38, cy + 4, ArtCommon._clamp(hh * 36 / 100, 11, 15), 8, 0, fg, 100, c.symbols[i]),
            ArtSVG.txt(462, cy + 4, ArtCommon._clamp(hh * 32 / 100, 10, 13), 4, 0, fg, 78, c.amountStrs[i])
        );
    }

    /// @dev TAPE — the holdings as a ticker running the full height of the card. Most
    ///      rows are ghosted at varying weight; two are pulled onto accent bars.
    function _tape(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        // Cap the legs that feed the ticker: a 16-position basket of long symbols makes
        // one pass ~460 bytes, and fifteen rows of that is 7KB of SVG for a texture the
        // eye reads as a loop anyway. Six legs fill the width at any realistic symbol
        // length; the exact count is stated in the header.
        string memory leg;
        uint256 legs = c.symbols.length > 6 ? 6 : c.symbols.length;
        for (uint256 i; i < legs; ++i) {
            leg = string.concat(leg, c.symbols[i], " ", c.amountStrs[i], unicode"   ·   ");
        }
        if (bytes(leg).length == 0) leg = unicode"STOCKPACK   ·   ";
        // Repeat rather than truncate: cutting at a byte offset can split the multi-byte
        // separator and emit invalid XML. Overshooting the card width is harmless.
        string memory rep = leg;
        for (uint256 k; k < 10 && bytes(rep).length < 150; ++k) {
            rep = string.concat(rep, leg);
        }

        uint256 f1 = 3 + ArtCommon._sb(c.seed, 6) % 5;
        uint256 f2 = f1 + 5 + ArtCommon._sb(c.seed, 7) % 4;
        uint256 ghost = p.light ? 22 : 20;

        o = ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0);
        for (uint256 i; i < 14; ++i) {
            uint256 yy = 96 + i * 27;
            if (yy > 448) break;
            int256 off = -int256((ArtCommon._pb(c.seed, i + 1, 1) % 190) + 8);
            if (i == f1 || i == f2) {
                o = string.concat(
                    o,
                    ArtSVG.rect(0, yy - 16, ArtCommon.W, 23, p.acc),
                    i % 2 == 0 ? "<g class='t1'>" : "<g class='t2'>",
                    ArtSVG.txt(off, yy, 13, 16, 0, p.light ? "#FFFFFF" : p.bg0, 100, rep),
                    "</g>"
                );
            } else {
                o = string.concat(
                    o,
                    i % 2 == 0 ? "<g class='t1'>" : "<g class='t2'>",
                    ArtSVG.txt(off, yy, 13, i % 3 == 0 ? 8 : 0, 0, p.ink, ghost + (i * 41) % 11, rep),
                    "</g>"
                );
            }
        }

        // header and footer plates: hard edges, so the name always reads over the tape
        return string.concat(
            o,
            ArtSVG.rect(0, 0, ArtCommon.W, 76, p.bg0),
            ArtSVG.line(0, 76, ArtCommon.W, 76, p.ink, 40),
            ArtCommon._eyebrow(24, 34, p, 0),
            // the ticker is a texture, not an inventory — the count has to be stated
            ArtSVG.txt(476, 34, 8, 4, 26, p.dim, 100, string.concat(c.total.toString(), " POS")),
            ArtSVG.txt(24, 62, ArtCommon._nameSize(340, bytes(c.name).length), 1 | 16, 0, p.ink, 100, c.name),
            ArtSVG.txt(476, 62, 20, 1 | 4 | 16, 0, p.dim, 100, ArtCommon._serial(c)),
            ArtSVG.rect(0, 452, ArtCommon.W, 48, p.bg0),
            ArtSVG.line(0, 452, ArtCommon.W, 452, p.ink, 40),
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    /// @dev MONOLITH — the tickers at poster scale, cropped by the frame. Size and
    ///      pitch are both functions of n, so one position becomes one enormous word.
    function _monolith(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 6 ? 6 : c.symbols.length;
        uint256 top = 128;
        uint256 step = n == 0 ? 296 : (424 - top) / n;
        uint256 size = ArtCommon._clamp(step * 62 / 100, 22, 62);
        uint256 accIdx = n == 0 ? 0 : ArtCommon._sb(c.seed, 3) % n;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            "<g transform='translate(490,472) rotate(-90)'>",
            ArtSVG.txt(
                0,
                0,
                42,
                1 | 32,
                0,
                p.ink,
                8,
                c.preview ? "PREVIEW" : string.concat("STOCKPACK #", c.tokenId.toString())
            ),
            "</g>",
            ArtCommon._eyebrow(24, 48, p, 0),
            ArtSVG.txt(24, 72, 15, 1 | 8, 0, p.dim, 100, c.name),
            ArtSVG.line(24, 88, 476, 88, p.ink, 35)
        );

        for (uint256 i; i < n; ++i) {
            // centred within its slot, not hung from the slot's top edge: at n=1 the
            // single word otherwise sat at the very top of a 296px band
            uint256 y = top + i * step + step / 2 + size * 18 / 100;
            bool acc = i == accIdx;
            o = string.concat(
                o,
                "<g class='",
                acc ? "ma m" : "mo m",
                (i % 7).toString(),
                "'>",
                ArtSVG.txt(22, y, size, 1 | 32, 0, acc ? p.acc : p.ink, acc ? 100 : 100 - i * 10, c.symbols[i]),
                "</g>",
                ArtSVG.txt(
                        478,
                        y - size * 6 / 100,
                        ArtCommon._clamp(size * 24 / 100, 10, 14),
                        4,
                        0,
                        p.dim,
                        100,
                        c.amountStrs[i]
                    ),
                ArtSVG.line(22, y + size * 28 / 100, 478, y + size * 28 / 100, p.dim, 25)
            );
        }
        return string.concat(
            o,
            c.total > n ? ArtSVG.txt(22, 444, 13, 1 | 16, 0, p.dim, 100, ArtCommon._more(c.total - n)) : "",
            ArtCommon._footer(c, p.dim, 100)
        );
    }
}
