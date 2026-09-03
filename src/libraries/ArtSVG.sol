// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title ArtSVG — SVG element primitives for the card art, as a *linked* library.
/// @dev   These are `public`, not `internal`, on purpose. As internal functions the
///        optimiser inlines them at every one of the ~50 call sites in StockPackArt,
///        which alone put that contract at ~69KB — nearly triple the EIP-170 limit.
///        Public library functions live in this library's own deployed bytecode and
///        are reached by DELEGATECALL, so there is exactly one copy. The extra call
///        cost is irrelevant: the only caller is a view path read off-chain.
///        (Same shape as Uniswap V3's linked NFTDescriptor library.)
library ArtSVG {
    using Strings for uint256;

    function sans() internal pure returns (string memory) {
        return "ui-sans-serif,system-ui,-apple-system,Helvetica,Arial,sans-serif";
    }

    function mono() internal pure returns (string memory) {
        return "ui-monospace,SFMono-Regular,Menlo,monospace";
    }

    /// @notice One `<text>` element.
    /// @param flags 1 sans, 2 anchor-middle, 4 anchor-end, 8 w600, 16 w700, 32 w800.
    /// @param ls10  letter-spacing in tenths of a px; 0 omits the attribute.
    /// @param op    opacity in hundredths; >=100 omits the attribute.
    /// @param body  MUST already be XML-escaped — escaping here would pull the escape
    ///              loop back into every caller.
    function txt(
        int256 x,
        uint256 y,
        uint256 size,
        uint256 flags,
        uint256 ls10,
        string memory fill,
        uint256 op,
        string memory body
    ) public pure returns (string memory) {
        return string.concat(
            "<text x='",
            itoa(x),
            "' y='",
            y.toString(),
            "' font-family='",
            flags & 1 != 0 ? sans() : mono(),
            "' font-size='",
            size.toString(),
            "'",
            flags & 8 != 0
                ? " font-weight='600'"
                : flags & 16 != 0 ? " font-weight='700'" : flags & 32 != 0 ? " font-weight='800'" : "",
            flags & 2 != 0 ? " text-anchor='middle'" : flags & 4 != 0 ? " text-anchor='end'" : "",
            ls10 == 0 ? "" : string.concat(" letter-spacing='", dec1(ls10), "'"),
            " fill='",
            fill,
            "'",
            op >= 100 ? "" : string.concat(" opacity='", pc(op), "'"),
            ">",
            body,
            "</text>"
        );
    }

    function line(uint256 x1, uint256 y1, uint256 x2, uint256 y2, string memory c, uint256 op)
        public
        pure
        returns (string memory)
    {
        return string.concat(
            "<line x1='",
            x1.toString(),
            "' y1='",
            y1.toString(),
            "' x2='",
            x2.toString(),
            "' y2='",
            y2.toString(),
            "' stroke='",
            c,
            "' stroke-opacity='",
            pc(op),
            "'/>"
        );
    }

    function rect(uint256 x, uint256 y, uint256 w, uint256 h, string memory fill) public pure returns (string memory) {
        return string.concat(
            "<rect x='",
            x.toString(),
            "' y='",
            y.toString(),
            "' width='",
            w.toString(),
            "' height='",
            h.toString(),
            "' fill='",
            fill,
            "'/>"
        );
    }

    /// @param stroke empty string omits the stroke attributes entirely.
    function circle(int256 cx, int256 cy, uint256 r, string memory fill, string memory stroke, uint256 sop)
        public
        pure
        returns (string memory)
    {
        return string.concat(
            "<circle cx='",
            itoa(cx),
            "' cy='",
            itoa(cy),
            "' r='",
            r.toString(),
            "' fill='",
            fill,
            "'",
            bytes(stroke).length == 0 ? "" : string.concat(" stroke='", stroke, "' stroke-opacity='", pc(sop), "'"),
            "/>"
        );
    }

    /// @notice Many stroked segments as ONE element. Sixty separate `<line>` tags for
    ///         the Orbit dial cost ~5.5KB of repeated attributes; the same geometry in
    ///         a single path `d` is about a third of that.
    function path(string memory d, string memory stroke, uint256 op) public pure returns (string memory) {
        return string.concat("<path d='", d, "' fill='none' stroke='", stroke, "' stroke-opacity='", pc(op), "'/>");
    }

    /// @dev One "move-to / line-to" segment for a `path` d-string.
    function seg(int256 x1, int256 y1, int256 x2, int256 y2) internal pure returns (string memory) {
        return string.concat("M", itoa(x1), " ", itoa(y1), "L", itoa(x2), " ", itoa(y2));
    }

    function radialGradient(string memory id, string memory c, uint256 cx, uint256 cy, uint256 r, uint256 op)
        public
        pure
        returns (string memory)
    {
        return string.concat(
            "<radialGradient id='",
            id,
            "' cx='",
            cx.toString(),
            "%' cy='",
            cy.toString(),
            "%' r='",
            r.toString(),
            "%'><stop offset='0' stop-color='",
            c,
            "' stop-opacity='",
            pc(op),
            "'/><stop offset='1' stop-color='",
            c,
            "' stop-opacity='0'/></radialGradient>"
        );
    }

    function gradientStop(string memory off, string memory c, uint256 op) public pure returns (string memory) {
        return string.concat("<stop offset='", off, "' stop-color='", c, "' stop-opacity='", pc(op), "'/>");
    }

    /// @dev "0.07" from 7, "0.34" from 34, "1" from >=100.
    function pc(uint256 h) internal pure returns (string memory) {
        if (h >= 100) return "1";
        if (h == 0) return "0";
        if (h < 10) return string.concat("0.0", h.toString());
        if (h % 10 == 0) return string.concat("0.", (h / 10).toString());
        return string.concat("0.", h.toString());
    }

    /// @dev "2.6" from 26, "1" from 10 — one decimal place, trailing zero trimmed.
    function dec1(uint256 t) internal pure returns (string memory) {
        return t % 10 == 0 ? (t / 10).toString() : string.concat((t / 10).toString(), ".", (t % 10).toString());
    }

    function itoa(int256 v) internal pure returns (string memory) {
        return v < 0 ? string.concat("-", uint256(-v).toString()) : uint256(v).toString();
    }
}
