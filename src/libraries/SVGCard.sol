// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title SVGCard — pure on-chain assembly of the 350×500 StockPack trading card.
/// @dev All attacker-controlled strings (symbols, bundle name) must already be
///      ASCII-sanitized by the caller; this library additionally XML-escapes them.
library SVGCard {
    using Strings for uint256;

    struct CardData {
        string name; // bundle name, sanitized, NOT yet XML-escaped
        uint256 tokenId; // 0 when preview
        uint64 sealedAt; // 0 when preview
        string[] symbols; // sanitized ASCII, max 11 chars each
        string[] amountStrs; // preformatted display amounts
        uint256 total; // total constituent count (rows may be capped below this)
        uint256 hue; // 0..359, deterministic from (name, creator)
        bool preview;
    }

    uint256 internal constant MAX_ROWS = 8;

    function render(CardData memory d) internal pure returns (string memory) {
        string memory hue = d.hue.toString();
        string memory rows = _rows(d);
        string memory footer = d.preview
            ? unicode"PREVIEW · UNSEALED"
            : string.concat(
                "StockPack #",
                d.tokenId.toString(),
                unicode" · SEALED ",
                formatDate(d.sealedAt),
                unicode" · 100% REDEEMABLE"
            );

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 350 500' width='350' height='500'>",
            "<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'>",
            "<stop offset='0' stop-color='hsl(",
            hue,
            ",45%,14%)'/><stop offset='1' stop-color='hsl(",
            hue,
            ",60%,7%)'/></linearGradient></defs>",
            "<rect width='350' height='500' rx='18' fill='url(#g)'/>",
            "<rect x='10' y='10' width='330' height='480' rx='12' fill='none' stroke='hsl(",
            hue,
            ",70%,55%)' stroke-opacity='0.55' stroke-width='1.5'/>",
            "<text x='30' y='52' font-family='ui-sans-serif,system-ui,sans-serif' font-size='11' letter-spacing='3' fill='hsl(",
            hue,
            ",70%,70%)'>STOCKPACK BUNDLE</text>",
            "<text x='30' y='86' font-family='ui-sans-serif,system-ui,sans-serif' font-size='21' font-weight='700' fill='#f5f2ea'>",
            escapeXML(d.name),
            "</text>",
            "<line x1='30' y1='106' x2='320' y2='106' stroke='hsl(",
            hue,
            ",60%,50%)' stroke-opacity='0.4'/>",
            rows,
            "<text x='175' y='474' text-anchor='middle' font-family='ui-monospace,monospace' font-size='9.5' letter-spacing='1' fill='hsl(",
            hue,
            ",30%,72%)'>",
            escapeXML(footer),
            "</text></svg>"
        );
    }

    function _rows(CardData memory d) private pure returns (string memory rows) {
        uint256 shown = d.symbols.length < MAX_ROWS ? d.symbols.length : MAX_ROWS;
        for (uint256 i; i < shown; ++i) {
            string memory y = (146 + i * 38).toString();
            rows = string.concat(
                rows,
                "<text x='30' y='",
                y,
                "' font-family='ui-monospace,monospace' font-size='16' font-weight='600' fill='#f5f2ea'>",
                escapeXML(d.symbols[i]),
                "</text><text x='320' y='",
                y,
                "' text-anchor='end' font-family='ui-monospace,monospace' font-size='16' fill='#cfc9bc'>",
                escapeXML(d.amountStrs[i]),
                "</text>"
            );
        }
        if (d.total > shown) {
            rows = string.concat(
                rows,
                "<text x='30' y='",
                (146 + shown * 38).toString(),
                "' font-family='ui-monospace,monospace' font-size='13' fill='#8f897d'>+",
                (d.total - shown).toString(),
                " more</text>"
            );
        }
    }

    /// @notice Display formatting: at most 2 trimmed decimals for amounts ≥ 0.01;
    ///         smaller amounts get up to 6 truncated decimals with trailing zeros
    ///         trimmed ("0.005", "0.000123") so fractional share counts render
    ///         honestly; below 10^-6 units, "<0.000001" — never a lying "0.00".
    function formatAmount(uint256 amount, uint8 decimals) internal pure returns (string memory) {
        if (amount == 0) return "0";
        uint256 dec = decimals > 77 ? 77 : decimals; // 10**78 would overflow
        uint256 unit = 10 ** dec;
        uint256 whole = amount / unit;
        // divide by unit/100 rather than multiply by 100: (amount % unit) * 100 overflows for dec >= 76
        uint256 frac2 = dec >= 2 ? (amount % unit) / (unit / 100) : (amount % unit) * 100 / unit;
        if (whole == 0 && frac2 == 0) return _formatSub001(amount, dec, unit);
        if (frac2 == 0) return whole.toString();
        if (frac2 % 10 == 0) return string.concat(whole.toString(), ".", (frac2 / 10).toString());
        if (frac2 < 10) return string.concat(whole.toString(), ".0", frac2.toString());
        return string.concat(whole.toString(), ".", frac2.toString());
    }

    /// @dev 0 < amount < 0.01 units: six truncated decimals, trailing zeros trimmed.
    ///      Unreachable for dec < 2 (whole > 0 or frac2 > 0 there).
    function _formatSub001(uint256 amount, uint256 dec, uint256 unit) private pure returns (string memory) {
        uint256 frac6 = dec >= 6 ? amount / (unit / 1e6) : amount * (10 ** (6 - dec));
        if (frac6 == 0) return "<0.000001";
        bytes memory buf = new bytes(6);
        uint256 last;
        uint256 v = frac6;
        for (uint256 i = 6; i > 0; --i) {
            uint256 digit = v % 10;
            v /= 10;
            buf[i - 1] = bytes1(uint8(48 + digit));
            if (digit != 0 && last == 0) last = i;
        }
        assembly ("memory-safe") {
            mstore(buf, last) // trim trailing zeros
        }
        return string.concat("0.", string(buf));
    }

    /// @notice days-from-civil inverse (Howard Hinnant's algorithm): unix ts → "YYYY-MM-DD".
    function formatDate(uint64 ts) internal pure returns (string memory) {
        uint256 z = uint256(ts) / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 y = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 day = doy - (153 * mp + 2) / 5 + 1;
        uint256 month = mp < 10 ? mp + 3 : mp - 9;
        if (month <= 2) y += 1;
        return string.concat(y.toString(), "-", _pad2(month), "-", _pad2(day));
    }

    function _pad2(uint256 v) private pure returns (string memory) {
        return v < 10 ? string.concat("0", v.toString()) : v.toString();
    }

    /// @notice Escapes &, <, >, ", ' for safe embedding in SVG text nodes/attributes.
    function escapeXML(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * 6); // worst case: every char becomes &quot;
        uint256 o;
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c == "&") {
                o = _append(out, o, "&amp;");
            } else if (c == "<") {
                o = _append(out, o, "&lt;");
            } else if (c == ">") {
                o = _append(out, o, "&gt;");
            } else if (c == '"') {
                o = _append(out, o, "&quot;");
            } else if (c == "'") {
                o = _append(out, o, "&apos;");
            } else {
                out[o] = c;
                ++o;
            }
        }
        assembly ("memory-safe") {
            mstore(out, o) // shrink to written length
        }
        return string(out);
    }

    function _append(bytes memory out, uint256 o, bytes memory entity) private pure returns (uint256) {
        for (uint256 i; i < entity.length; ++i) {
            out[o + i] = entity[i];
        }
        return o + entity.length;
    }
}
