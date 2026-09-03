// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICardArt} from "../interfaces/ICardArt.sol";
import {ArtCommon} from "./ArtCommon.sol";
import {ArtSVG} from "./ArtSVG.sol";
import {SVGCard} from "./SVGCard.sol";

/// @title ArtEditionsB — card compositions, set B. Linked library.
/// @dev   Same contract as set A: `public` entry points so the code lives here rather
///        than inlining into StockPackArt, and every edition must compose at n=1 as
///        well as n=16. The split into two libraries exists only because ten editions
///        of SVG template do not fit under EIP-170's 24,576 bytes in one place.
library ArtEditionsB {
    using Strings for uint256;

    /// @dev MOSAIC — the basket as a tiled field rather than a list. Tiles are laid on
    ///      a near-square grid and the last tile in each row stretches to the edge, so
    ///      the plate is always fully packed whatever the position count. Type scales
    ///      per tile, so a single position becomes one poster-sized tile.
    function _mosaic(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 12 ? 12 : c.symbols.length;
        uint256 cols = n <= 1 ? 1 : n <= 4 ? 2 : n <= 9 ? 3 : 4;
        uint256 rows = n == 0 ? 1 : (n + cols - 1) / cols;
        uint256 x0 = 24;
        uint256 y0 = 116;
        uint256 gw = 452;
        uint256 gh = 334;
        uint256 th = gh / rows;
        uint256 accIdx = n == 0 ? 0 : ArtCommon._sb(c.seed, 5) % n;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            ArtCommon._eyebrow(24, 46, p, 0),
            ArtSVG.txt(24, 86, ArtCommon._nameSize(340, bytes(c.name).length), 1 | 16, 0, p.ink, 100, c.name),
            ArtSVG.txt(476, 86, 22, 1 | 4 | 16, 0, p.dim, 100, ArtCommon._serial(c))
        );

        for (uint256 i; i < n; ++i) {
            uint256 r = i / cols;
            uint256 col = i % cols;
            uint256 tw = gw / cols;
            // last tile of a row absorbs the rounding remainder, so rows always meet
            // the right edge and the grid never shows a ragged gutter
            if (col == cols - 1 || i == n - 1) tw = gw - col * (gw / cols);
            uint256 tileX = x0 + col * (gw / cols);
            uint256 ty = y0 + r * th;
            uint256 hh = r == rows - 1 ? gh - r * th : th;
            o = string.concat(o, _tile(c, p, i, tileX, ty, tw, hh, i == accIdx));
        }

        return string.concat(
            o,
            string.concat(
                "<rect x='24' y='116' width='452' height='334' fill='none' stroke='", p.ink, "' stroke-opacity='0.5'/>"
            ),
            c.total > n ? ArtSVG.txt(24, 462, 8, 0, 10, p.dim, 100, ArtCommon._more(c.total - n)) : "",
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    function _tile(
        ICardArt.Card memory c,
        ArtCommon.P memory p,
        uint256 i,
        uint256 x,
        uint256 y,
        uint256 w,
        uint256 h,
        bool acc
    ) private pure returns (string memory) {
        string memory fg = acc ? (p.light ? "#FFFFFF" : p.bg0) : p.ink;
        string memory o = string.concat(
            "<g class='pu m",
            (i % 7).toString(),
            "'>",
            ArtSVG.rect(x, y, w, h, acc ? p.acc : (i % 3 == 1 ? p.bg1 : p.bg0)),
            "</g>",
            string.concat(
                "<rect x='",
                x.toString(),
                "' y='",
                y.toString(),
                "' width='",
                w.toString(),
                "' height='",
                h.toString(),
                "' fill='none' stroke='",
                p.dim,
                "' stroke-opacity='0.35'/>"
            )
        );
        // one poster tile, or a dense grid cell — the tile's own size decides
        if (w > 220 && h > 150) {
            return string.concat(
                o,
                ArtSVG.txt(int256(x + 18), y + h / 2 - 4, 52, 1 | 32, 0, fg, 100, c.symbols[i]),
                ArtSVG.line(x + 18, y + h / 2 + 14, x + w - 18, y + h / 2 + 14, fg, 35),
                ArtSVG.txt(int256(x + 18), y + h / 2 + 46, 24, 0, 0, fg, 85, c.amountStrs[i]),
                ArtSVG.txt(int256(x + w - 14), y + 26, 11, 4, 14, fg, 60, ArtCommon._two(i + 1))
            );
        }
        uint256 fs = ArtCommon._clamp(w / 7, 11, 26);
        return string.concat(
            o,
            ArtSVG.txt(int256(x + 12), y + h / 2, fs, 1 | 32, 0, fg, 100, ArtCommon._trunc(c.symbols[i], w / 13)),
            ArtSVG.txt(
                int256(x + 12), y + h / 2 + fs, ArtCommon._clamp(fs * 55 / 100, 9, 14), 0, 0, fg, 75, c.amountStrs[i]
            ),
            ArtSVG.txt(int256(x + w - 10), y + 18, 9, 4, 12, fg, 55, ArtCommon._two(i + 1))
        );
    }

    /// @dev TERMINAL — the pack() call as a console session. Reads as a transcript
    ///      rather than a card, which is the point: the basket is the command output.
    ///      Short baskets get more of the preamble so the window never half-empties.
    function _terminal(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 9 ? 9 : c.symbols.length;
        uint256 lh = 22;
        uint256 y = 118;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            ArtSVG.rect(24, 24, 452, 452, p.bg1),
            string.concat(
                "<rect x='24' y='24' width='452' height='452' fill='none' stroke='", p.dim, "' stroke-opacity='0.45'/>"
            ),
            // window chrome
            ArtSVG.rect(24, 24, 452, 34, p.bg0),
            ArtSVG.line(24, 58, 476, 58, p.dim, 45),
            ArtSVG.circle(42, 41, 4, p.dim, "", 0),
            ArtSVG.circle(58, 41, 4, p.dim, "", 0),
            ArtSVG.circle(74, 41, 4, p.acc, "", 0),
            ArtSVG.txt(250, 45, 9, 2, 14, p.dim, 100, unicode"stockpack — pack"),
            // CRT band: the caret alone is 126px on a 250,000px card, far too small
            // to register as motion. This sweeps the whole screen.
            // group opacity, not a solid fill: an opaque band would wipe the terminal
            // contents as it passed. It also has to stay subtle when the animation is
            // off, which is why the transparency lives on the element, not a keyframe.
            "<g class='cr' opacity='0.07'>",
            ArtSVG.rect(24, 24, 452, 30, p.ink),
            "</g>"
        );

        o = string.concat(
            o,
            _line(p, 44, y, "$ ", string.concat("stockpack pack --name \"", ArtCommon._trunc(c.name, 22), "\"")),
            _out(p, 44, y + lh, string.concat("reading wallet ... ", c.total.toString(), " position(s)")),
            _out(p, 44, y + lh * 2, "verifying balances ... ok")
        );
        y += lh * 3;
        // pad the preamble when the basket is short so the window stays full
        if (n < 5) {
            o = string.concat(o, _out(p, 44, y, unicode"fee 0.00% · oracle none"));
            y += lh;
        }
        if (n < 3) {
            o = string.concat(o, _out(p, 44, y, "escrow 0x52Ba...f387"));
            y += lh;
        }
        y += 8;

        for (uint256 i; i < n; ++i) {
            uint256 ly = y + i * lh;
            o = string.concat(
                o,
                ArtSVG.txt(60, ly, 13, 8, 0, p.acc, 100, "+"),
                ArtSVG.txt(80, ly, 13, 8, 0, p.ink, 100, c.symbols[i]),
                ArtSVG.txt(456, ly, 13, 4, 0, p.dim, 100, c.amountStrs[i])
            );
        }
        y += n * lh;
        if (c.total > n) {
            o = string.concat(o, _out(p, 44, y, string.concat("... ", (c.total - n).toString(), " more")));
            y += lh;
        }

        return string.concat(
            o,
            _out(
                p,
                44,
                y + 12,
                c.preview
                    ? unicode"preview · unsealed"
                    : string.concat("sealed #", c.tokenId.toString(), " ", SVGCard.formatDate(c.sealedAt))
            ),
            ArtSVG.txt(44, y + 12 + lh, 13, 8, 0, p.acc, 100, "$"),
            "<g class='bk'>",
            ArtSVG.rect(60, y + 2 + lh, 9, 14, p.ink),
            "</g>",
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    function _line(ArtCommon.P memory p, uint256 x, uint256 y, string memory sigil, string memory body)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            ArtSVG.txt(int256(x), y, 13, 8, 0, p.acc, 100, sigil),
            ArtSVG.txt(int256(x + 18), y, 13, 0, 0, p.ink, 100, body)
        );
    }

    function _out(ArtCommon.P memory p, uint256 x, uint256 y, string memory body) private pure returns (string memory) {
        return string.concat(
            ArtSVG.txt(int256(x), y, 13, 0, 0, p.dim, 70, ">"),
            ArtSVG.txt(int256(x + 18), y, 13, 0, 0, p.dim, 100, body)
        );
    }

    /// @dev SPLITFLAP — an airport departure board. Each position is a row of flap
    ///      cells, split by the hairline every mechanical display has. Cell size is a
    ///      function of the row height, so one position gets a board-sized ticker.
    function _splitflap(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 7 ? 7 : c.symbols.length;
        uint256 span = 334;
        uint256 rh = n == 0 ? span : ArtCommon._clamp(span / n, 30, 96);
        uint256 slack = n * rh < span ? (span - n * rh) / 2 : 0;
        uint256 top = 116 + slack;
        uint256 accIdx = n == 0 ? 0 : ArtCommon._sb(c.seed, 5) % n;

        o = string.concat(
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            ArtCommon._eyebrow(24, 46, p, 0),
            ArtSVG.txt(24, 86, ArtCommon._nameSize(340, bytes(c.name).length), 1 | 16, 0, p.ink, 100, c.name),
            ArtSVG.txt(476, 86, 22, 1 | 4 | 16, 0, p.dim, 100, ArtCommon._serial(c))
        );

        for (uint256 i; i < n; ++i) {
            o = string.concat(o, _flapRow(c, p, i, top + i * rh, rh, i == accIdx));
        }
        return string.concat(
            o,
            c.total > n ? ArtSVG.txt(24, 462, 8, 0, 10, p.dim, 100, ArtCommon._more(c.total - n)) : "",
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    function _flapRow(ICardArt.Card memory c, ArtCommon.P memory p, uint256 i, uint256 y, uint256 rh, bool acc)
        private
        pure
        returns (string memory o)
    {
        uint256 ch = rh > 12 ? rh - 10 : rh; // cell height, leaving the row gutter
        uint256 cw = ArtCommon._clamp(ch * 72 / 100, 16, 40);
        string memory sym = ArtCommon._trunc(c.symbols[i], 8);
        uint256 cells = bytes(sym).length;
        if (cells == 0) return "";
        uint256 block_ = cells * cw + (cells - 1) * 4;
        string memory fill = acc ? p.acc : p.bg1;
        string memory fg = acc ? (p.light ? "#FFFFFF" : p.bg0) : p.ink;
        uint256 fs = ArtCommon._clamp(ch * 58 / 100, 11, 34);

        // One background rect, dividers, one split line and ONE text element. Drawn as
        // a rect+line+text per character this cost ~300 bytes a cell — 20KB of SVG at
        // sixteen positions — and split the ticker into single glyphs, so the symbol
        // never appeared as a readable string in the document.
        o = string.concat("<g class='fp f", (i % 7).toString(), "'>", ArtSVG.rect(24, y, block_, ch, fill));
        for (uint256 k = 1; k < cells; ++k) {
            uint256 dx = 24 + k * (cw + 4) - 2;
            o = string.concat(o, ArtSVG.line(dx, y, dx, y + ch, p.bg0, acc ? 45 : 70));
        }
        // the flap split: the one line that makes this read as a mechanism
        o = string.concat(o, ArtSVG.line(24, y + ch / 2, 24 + block_, y + ch / 2, p.bg0, acc ? 45 : 70));

        // textLength + lengthAdjust distributes the glyphs across the cells evenly;
        // the inset centres the first and last glyph in their own cell.
        uint256 inset = cw > fs * 6 / 10 ? (cw - fs * 6 / 10) / 2 : 0;
        o = string.concat(
            o,
            "<text x='",
            (24 + inset).toString(),
            "' y='",
            (y + ch / 2 + ch * 22 / 100).toString(),
            "' textLength='",
            (block_ - inset * 2).toString(),
            "' lengthAdjust='spacing' font-family='ui-monospace,SFMono-Regular,Menlo,monospace' font-size='",
            fs.toString(),
            "' font-weight='700' fill='",
            fg,
            "'>",
            sym,
            "</text>"
        );
        return string.concat(
            o,
            "</g>",
            ArtSVG.txt(476, y + ch / 2 + 5, ArtCommon._clamp(ch * 34 / 100, 11, 18), 4, 0, p.dim, 100, c.amountStrs[i])
        );
    }

    /// @dev GUILLOCHE — the banknote rosette, the rarest edition. Concentric rings whose
    ///      radius is sine-modulated; the petal count is derived from the basket size, so
    ///      the engraving is a portrait of the position count rather than decoration.
    function _guilloche(ICardArt.Card memory c, ArtCommon.P memory p) public pure returns (string memory o) {
        uint256 n = c.symbols.length > 6 ? 6 : c.symbols.length;
        uint256 petals = 5 + (c.total % 7);

        o = string.concat(ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0), ArtCommon._frame(p));
        // Seven thin rings with different petal counts. The look does not come from any
        // one curve but from their interference — four fat rings read as a doodle,
        // seven fine ones read as engraving.
        // One slow rotation for the whole rosette: 62s, so it reads as drift rather
        // than spin. Wrapped in a single <g> so it is one composited layer, not seven.
        o = string.concat(o, "<g class='sp'>");
        for (uint256 ring; ring < 7; ++ring) {
            o = string.concat(
                o,
                ArtSVG.path(
                    _rosette(int256(84 + ring * 20), int256(9 + (ring % 3) * 5), petals + ring * 2),
                    ring % 2 == 0 ? p.acc : p.ink,
                    ring % 2 == 0 ? 30 : 20
                )
            );
        }
        o = string.concat(o, "</g>");

        uint256 ph = 50 + n * 26;
        uint256 py = ArtCommon._clamp(268 - ph / 2, 122, 416 - ph);
        o = string.concat(
            o,
            ArtSVG.rect(76, py, 348, ph, p.bg0),
            string.concat(
                "<rect x='76' y='",
                py.toString(),
                "' width='348' height='",
                ph.toString(),
                "' fill='none' stroke='",
                p.acc,
                "' stroke-opacity='0.6'/>"
            ),
            ArtCommon._eyebrow(250, py + 22, p, 2),
            ArtSVG.txt(250, py + 46, ArtCommon._nameSize(300, bytes(c.name).length), 1 | 2 | 16, 0, p.ink, 100, c.name)
        );
        for (uint256 i; i < n; ++i) {
            uint256 ly = py + 72 + i * 26;
            o = string.concat(
                o,
                ArtSVG.txt(98, ly, 13, 8, 0, p.ink, 100, c.symbols[i]),
                ArtSVG.txt(402, ly, 13, 4, 0, p.dim, 100, c.amountStrs[i]),
                i + 1 < n ? ArtSVG.line(98, ly + 9, 402, ly + 9, p.dim, 22) : ""
            );
        }
        return string.concat(
            o,
            ArtSVG.txt(250, 440, 8, 2, 18, p.acc, 100, unicode"REDEEMABLE 1:1 · BEARER INSTRUMENT"),
            c.total > n ? ArtSVG.txt(24, 462, 8, 0, 10, p.dim, 100, ArtCommon._more(c.total - n)) : "",
            ArtCommon._footer(c, p.dim, 100)
        );
    }

    /// @dev One closed rosette ring: 48 points at r = base + amp*sin(petals*theta).
    ///      Emitted as a single path — 48 separate elements would cost several KB.
    function _rosette(int256 base, int256 amp, uint256 petals) private pure returns (string memory d) {
        for (uint256 k; k <= 48; ++k) {
            int256 a = int256(k) * 15 / 2; // 7.5 degrees per step, 360 total
            int256 r = base + amp * ArtCommon._sin(a * int256(petals)) / 10000;
            int256 x = 250 + r * ArtCommon._cos(a) / 10000;
            int256 y = 268 + r * ArtCommon._sin(a) / 10000;
            d = string.concat(d, k == 0 ? "M" : "L", ArtSVG.itoa(x), " ", ArtSVG.itoa(y));
        }
        return string.concat(d, "Z");
    }

    /// @dev AURORA — the rare one. Colour fields from stacked radial gradients (no
    ///      filters, so it rasterises identically everywhere) with the data in a glass
    ///      panel that grows with the basket and centres on what is left.
    function _aurora(ICardArt.Card memory c, ArtCommon.P memory p, string memory uid)
        public
        pure
        returns (string memory o)
    {
        uint256 n = c.symbols.length > 7 ? 7 : c.symbols.length;
        uint256 a1 = 14 + ArtCommon._sb(c.seed, 1) % 64;
        uint256 a2 = 16 + ArtCommon._sb(c.seed, 2) % 62;

        // accent + bg1 only: mixing the ink colour into the field turns every palette to mud
        o = string.concat(
            "<defs>",
            ArtSVG.radialGradient(string.concat("a", uid), p.acc, a1, 18, 66, 95),
            ArtSVG.radialGradient(string.concat("b", uid), p.bg1, 100 - a2, 52, 62, 100),
            ArtSVG.radialGradient(string.concat("c", uid), p.acc, 62, 100, 74, 60),
            "</defs>",
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, p.bg0),
            "<g class='dr'>",
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, string.concat("url(#b", uid, ")")),
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, string.concat("url(#a", uid, ")")),
            ArtSVG.rect(0, 0, ArtCommon.W, ArtCommon.H, string.concat("url(#c", uid, ")")),
            "</g>"
        );

        // an outsized ghost ticker behind the glass keeps sparse baskets from going empty
        if (n > 0) o = string.concat(o, ArtSVG.txt(250, 300, 130, 1 | 2 | 32, 0, p.ink, 9, c.symbols[0]));

        uint256 ph = 30 + n * 30;
        uint256 py = ArtCommon._clamp(300 - ph / 2, 112, 430 - ph);
        o = string.concat(
            o,
            ArtCommon._eyebrow(28, 50, p, 0),
            ArtSVG.txt(28, 88, ArtCommon._nameSize(340, bytes(c.name).length), 1 | 16, 0, p.ink, 100, c.name),
            ArtSVG.txt(472, 88, 22, 1 | 4 | 16, 0, p.ink, 60, ArtCommon._serial(c)),
            "<rect x='22' y='",
            py.toString(),
            "' width='456' height='",
            ph.toString(),
            "' fill='",
            p.bg0,
            "' opacity='0.5'/><rect x='22' y='",
            py.toString(),
            "' width='456' height='",
            ph.toString(),
            "' fill='none' stroke='",
            p.ink,
            "' stroke-opacity='0.45'/>"
        );

        for (uint256 i; i < n; ++i) {
            uint256 y = py + 28 + i * 30;
            o = string.concat(
                o,
                ArtSVG.txt(38, y, 13, 8, 0, p.ink, 100, c.symbols[i]),
                ArtSVG.txt(462, y, 13, 4, 0, p.ink, 78, c.amountStrs[i]),
                i + 1 < n ? ArtSVG.line(38, y + 10, 462, y + 10, p.ink, 18) : ""
            );
        }
        return string.concat(
            o,
            c.total > n ? ArtSVG.txt(28, 452, 8, 0, 10, p.ink, 70, ArtCommon._more(c.total - n)) : "",
            ArtCommon._footer(c, p.ink, 78)
        );
    }
}
