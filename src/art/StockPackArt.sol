// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ICardArt} from "../interfaces/ICardArt.sol";
import {ArtCommon} from "../libraries/ArtCommon.sol";
import {ArtEditions} from "../libraries/ArtEditions.sol";
import {ArtEditionsB} from "../libraries/ArtEditionsB.sol";
import {ArtEditionsC} from "../libraries/ArtEditionsC.sol";
import {ArtSVG} from "../libraries/ArtSVG.sol";

/// @title StockPackArt — the generative card artwork, fully on-chain.
/// @notice Ten editions, twelve palettes, five finishes and a derived rarity tier, all
///         selected from one seed (keccak(name, creator)) and composed against the
///         basket itself. Pure: holds no state, reads no storage, and is reachable only
///         through the renderer's view path — it provably cannot touch escrowed funds.
/// @dev    A thin dispatcher over four linked libraries. Inlined into a single contract
///         the compositions measure well past EIP-170's 24,576 bytes, so ArtEditions and
///         ArtEditionsB each hold half, ArtCommon holds shared chrome and ArtSVG the
///         element primitives.
contract StockPackArt is ICardArt {
    using Strings for uint256;

    // ── Traits ──────────────────────────────────────────────────────────────

    /// @inheritdoc ICardArt
    /// @dev Cumulative weights over one seed byte each, so rarity is legible and fixed
    ///      forever: Ledger is the house style at ~17%, Guilloche turns up on about one
    ///      card in forty. The last four palettes and last two finishes are the rare
    ///      band — together they are what pushes a card into the upper tiers.
    function traits(uint256 seed) public pure returns (uint256 edition, uint256 palette, uint256 finish) {
        uint256 e = seed & 0xff;
        edition = e < 44
            ? 0
            : e < 82
                ? 1
                : e < 116 ? 2 : e < 148 ? 3 : e < 176 ? 4 : e < 202 ? 5 : e < 224 ? 6 : e < 240 ? 7 : e < 250 ? 8 : 9;

        uint256 pa = (seed >> 8) & 0xff;
        // eight commons at ~10.5% each, four rares at ~3.9% each
        palette = pa < 216 ? pa / 27 : 8 + (pa - 216) / 10 > 11 ? 11 : 8 + (pa - 216) / 10;

        uint256 f = (seed >> 16) & 0xff;
        finish = f < 120 ? 0 : f < 180 ? 1 : f < 224 ? 2 : f < 248 ? 3 : 4;
    }

    /// @inheritdoc ICardArt
    function traitNames(uint256 edition, uint256 palette, uint256 finish)
        external
        pure
        returns (string memory, string memory, string memory, string memory)
    {
        string[10] memory eds = [
            "Ledger", "Strata", "Tape", "Mosaic", "Terminal", "Orbit", "Splitflap", "Monolith", "Aurora", "Guilloche"
        ];
        string[12] memory pals = [
            "Obsidian",
            "Bone",
            "Vellum",
            "Cobalt",
            "Oxide",
            "Chlorophyll",
            "Ash",
            "Plum",
            "Gilt",
            "Glacier",
            "Vapor",
            "Ember"
        ];
        string[5] memory fins = ["Matte", "Etched", "Foil", "Gilded", "Engraved"];
        return (eds[edition % 10], pals[palette % 12], fins[finish % 5], _tier(edition, palette, finish));
    }

    /// @dev Rarity points: the scarcer half of the editions, a rare palette, and the
    ///      rare finishes each contribute. Deriving the tier rather than rolling it
    ///      separately means the badge can never disagree with the picture.
    function _tier(uint256 edition, uint256 palette, uint256 finish) private pure returns (string memory) {
        uint256 pts;
        if (edition == 9 || edition == 8) pts += 3;
        else if (edition == 7 || edition == 6) pts += 2;
        else if (edition == 5 || edition == 4 || edition == 3) pts += 1;
        if (palette >= 8) pts += 2;
        if (finish == 4) pts += 3;
        else if (finish == 3) pts += 2;
        else if (finish == 2) pts += 1;
        return pts >= 6 ? "Mythic" : pts >= 4 ? "Rare" : pts >= 2 ? "Uncommon" : "Common";
    }

    // ── Entry point ─────────────────────────────────────────────────────────

    /// @inheritdoc ICardArt
    function render(Card calldata c) external pure returns (string memory) {
        (uint256 ed, uint256 pi, uint256 fin) = traits(c.seed);
        ArtCommon.P memory p = _palette(pi);
        // Gradient and pattern ids must be unique per card: marketplace galleries and
        // our own bundle grid put several cards in one DOM, and duplicate ids mean the
        // first definition silently wins for every later card that references it.
        string memory uid = c.preview ? "p" : c.tokenId.toString();

        string memory body;
        if (ed == 0) body = ArtEditions._ledger(c, p);
        else if (ed == 1) body = ArtEditions._strata(c, p);
        else if (ed == 2) body = ArtEditions._tape(c, p);
        else if (ed == 3) body = ArtEditionsB._mosaic(c, p);
        else if (ed == 4) body = ArtEditionsB._terminal(c, p);
        else if (ed == 5) body = ArtEditionsC._orbit(c, p);
        else if (ed == 6) body = ArtEditionsB._splitflap(c, p);
        else if (ed == 7) body = ArtEditions._monolith(c, p);
        else if (ed == 8) body = ArtEditionsB._aurora(c, p, uid);
        else body = ArtEditionsB._guilloche(c, p);

        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 500 500' width='1000' height='1000'>",
            _motion(ed),
            body,
            _finish(fin, p, uid),
            _sheen(),
            "</svg>"
        );
    }

    function _palette(uint256 i) private pure returns (ArtCommon.P memory) {
        if (i == 0) return ArtCommon.P("#0B0B0C", "#17181A", "#F2EFE9", "#8A8781", "#E8B44F", false);
        if (i == 1) return ArtCommon.P("#EDE9E0", "#FCFAF4", "#14140F", "#6E6A5F", "#C6362B", true);
        if (i == 2) return ArtCommon.P("#E8E3D5", "#F5F1E6", "#1B2019", "#6B7065", "#2F6B4F", true);
        if (i == 3) return ArtCommon.P("#0A1633", "#12224A", "#E8EEFF", "#7E8DB5", "#4C8DFF", false);
        if (i == 4) return ArtCommon.P("#2A1410", "#3B1D16", "#F6E7DC", "#A88374", "#E2622F", false);
        if (i == 5) return ArtCommon.P("#08170D", "#0E2415", "#E6F5E8", "#78A386", "#4BD07C", false);
        if (i == 6) return ArtCommon.P("#26262A", "#313137", "#F0F0F2", "#9A9AA2", "#FF7A3D", false);
        if (i == 7) return ArtCommon.P("#1A0A22", "#260F32", "#F3E9F7", "#A184AE", "#E85FB0", false);
        // ── the rare band ───────────────────────────────────────────────────
        if (i == 8) return ArtCommon.P("#0A0A08", "#16150F", "#F5E6C8", "#A08B5F", "#D4AF37", false); // Gilt
        if (i == 9) return ArtCommon.P("#E6EDF2", "#F6FAFD", "#0F1E28", "#5A7181", "#0A84FF", true); // Glacier
        if (i == 10) return ArtCommon.P("#150A24", "#221037", "#F0E6FF", "#9B7FC4", "#00E5D0", false); // Vapor
        return ArtCommon.P("#0C0708", "#170C0E", "#FFEDE8", "#A07F79", "#FF3B2F", false); // Ember
    }

    /// @dev Etched is a hatch; Foil a set of crisp diagonal sweeps. The two rare
    ///      finishes are deliberately NOT overlays: a spectrum wash over the card
    ///      looked cheap and, worse, dropped the contrast of the numbers underneath.
    ///      Gilded and Engraved are metalwork on the border instead — unmistakable at
    ///      thumbnail size, and they never touch the data. Light palettes get the
    ///      gradients at reduced strength and without screen blending, since
    ///      screen-blending white onto cream just bleaches the card.
    function _finish(uint256 kind, ArtCommon.P memory p, string memory uid) private pure returns (string memory) {
        if (kind == 0) return "";
        if (kind == 1) {
            return string.concat(
                "<defs><pattern id='h",
                uid,
                "' width='5' height='5' patternUnits='userSpaceOnUse' patternTransform='rotate(45)'>",
                "<line x1='0' y1='0' x2='0' y2='5' stroke='",
                p.ink,
                "' stroke-width='0.7'/></pattern></defs><rect width='500' height='500' fill='url(#h",
                uid,
                ")' opacity='",
                p.light ? "0.08" : "0.09",
                "'/>"
            );
        }
        uint256 k = p.light ? 45 : 100; // light grounds bleach out long before dark ones
        string memory stops;
        if (kind == 2) {
            stops = string.concat(
                ArtSVG.gradientStop("0.18", "#FFFFFF", 0),
                ArtSVG.gradientStop("0.30", "#FFFFFF", 20 * k / 100),
                ArtSVG.gradientStop("0.37", p.acc, 34 * k / 100),
                ArtSVG.gradientStop("0.44", "#FFFFFF", 5 * k / 100),
                ArtSVG.gradientStop("0.60", p.acc, 22 * k / 100),
                ArtSVG.gradientStop("0.70", "#FFFFFF", 16 * k / 100),
                ArtSVG.gradientStop("0.82", "#FFFFFF", 0)
            );
        } else {
            // kinds 3 and 4 are frame work, not overlays — see _frameFinish
            return _frameFinish(kind, p, uid);
        }
        return string.concat(
            "<defs><linearGradient id='fo",
            uid,
            "' x1='0' y1='1' x2='1' y2='0'>",
            stops,
            "</linearGradient></defs><rect width='500' height='500' fill='url(#fo",
            uid,
            ")'",
            p.light ? "" : " style='mix-blend-mode:screen'",
            "/>"
        );
    }

    /// @dev Gilded: a double keyline with corner ticks, struck in the palette's accent.
    ///      Engraved: the same keylines plus a fine guilloche wave run around all four
    ///      borders. The wave is defined once and `<use>`d four times, which costs about
    ///      700 bytes instead of the ~2.5KB four separate paths would.
    function _frameFinish(uint256 kind, ArtCommon.P memory p, string memory uid) private pure returns (string memory) {
        string memory keylines = string.concat(
            "<g fill='none' stroke='",
            p.acc,
            "'><rect x='7' y='7' width='486' height='486' stroke-opacity='0.85'/>",
            "<rect x='11' y='11' width='478' height='478' stroke-opacity='0.35'/></g>"
        );
        // corner ticks: short right angles just inside the keyline
        string memory ticks = string.concat(
            "<g fill='none' stroke='",
            p.acc,
            "' stroke-opacity='0.9' stroke-width='2'>",
            "<path d='M7 30V7h23M470 7h23v23M493 470v23h-23M30 493H7v-23'/></g>"
        );
        if (kind == 3) return string.concat(keylines, ticks);

        // The wave lives in the outer margin (8..16px from each edge). Further in it
        // crossed the footer line, which sits at y=477 on every edition — an ornament
        // that reduces legibility is the exact thing this finish replaced.
        string memory wave;
        for (uint256 k; k <= 50; ++k) {
            int256 x = int256(k) * 10;
            int256 y = 12 + ArtCommon._sin(int256(k) * 72) * 4 / 10000;
            wave = string.concat(wave, k == 0 ? "M" : "L", ArtSVG.itoa(x), " ", ArtSVG.itoa(y));
        }
        return string.concat(
            "<defs><path id='w",
            uid,
            "' d='",
            wave,
            "'/></defs><g fill='none' stroke='",
            p.acc,
            "' stroke-opacity='0.55'><use href='#w",
            uid,
            "'/><use href='#w",
            uid,
            "' transform='translate(500,500) rotate(180)'/><use href='#w",
            uid,
            "' transform='translate(0,500) rotate(-90)'/><use href='#w",
            uid,
            "' transform='translate(500,0) rotate(90)'/></g><g fill='none' stroke='",
            p.acc,
            "'><rect x='20' y='20' width='460' height='460' stroke-opacity='0.7'/>",
            "<rect x='24' y='24' width='452' height='452' stroke-opacity='0.28'/></g>"
        );
    }

    /// @dev Declarative CSS animation carried inside the document itself, so the card
    ///      moves wherever it is displayed — a wallet, a marketplace tile, an <img> on
    ///      any site — not only where we control the page. SMIL is avoided (long on
    ///      Chrome's deprecation path); CSS animation in SVG is universally supported
    ///      and, critically, still runs inside <img>, where scripting does not.
    ///
    ///      Emitted PER EDITION rather than as one shared block: every byte here ships
    ///      on every card, and a Splitflap has no use for the orrery keyframes. The
    ///      reduced-motion guard travels with it — a card that ignores the viewer's
    ///      accessibility setting is broken art, not bold art.
    function _motion(uint256 ed) private pure returns (string memory) {
        string memory k = "@keyframes sh{0%{transform:translateX(-70%)}55%,100%{transform:translateX(120%)}}"
            ".sh{animation:sh 7s cubic-bezier(.4,0,.2,1) infinite}";

        if (ed == 5) {
            // Orrery. Rings turn at different rates and the outer one runs backwards,
            // so the composition never repeats a pose. Each node counter-rotates at
            // exactly its ring's period, which keeps every ticker upright — a label
            // that tumbles with the ring is unreadable within one revolution.
            k = string.concat(
                k,
                "@keyframes r1{to{transform:rotate(360deg)}}@keyframes r2{to{transform:rotate(-360deg)}}",
                ".oi,.oo,.dl{transform-origin:250px 248px}",
                ".oi{animation:r1 17s linear infinite}.oo{animation:r2 25s linear infinite}",
                ".dl{animation:r1 70s linear infinite}",
                ".ci,.co{transform-box:fill-box;transform-origin:center}",
                ".ci{animation:r2 17s linear infinite}.co{animation:r1 25s linear infinite}"
            );
        } else if (ed == 2) {
            // The tape runs. Alternate rows travel opposite ways so the field shears
            // rather than sliding as one sheet.
            k = string.concat(
                k,
                "@keyframes t1{to{transform:translateX(-190px)}}@keyframes t2{to{transform:translateX(190px)}}",
                ".t1{animation:t1 9s linear infinite alternate}.t2{animation:t2 11s linear infinite alternate}"
            );
        } else if (ed == 4) {
            // A terminal that does not blink is a screenshot. The CRT band is what
            // makes it read as a live screen from across a room — the caret alone is
            // 126 square pixels on a 250,000 pixel card.
            k = string.concat(
                k,
                "@keyframes bk{0%,45%{opacity:1}55%,100%{opacity:0}}.bk{animation:bk 1.05s step-end infinite}",
                "@keyframes cr{0%{transform:translateY(0)}100%{transform:translateY(392px)}}",
                ".cr{animation:cr 4.2s linear infinite}"
            );
        } else if (ed == 9) {
            k = string.concat(
                k,
                "@keyframes sp{to{transform:rotate(360deg)}}.sp{animation:sp 26s linear infinite;transform-origin:250px 268px}"
            );
        } else if (ed == 6) {
            // Every row turns over, staggered, the way a departure board settles.
            k = string.concat(
                k,
                "@keyframes fp{0%,70%,100%{transform:scaleY(1)}80%{transform:scaleY(.05)}}",
                ".fp{transform-box:fill-box;transform-origin:center;animation:fp 3.4s ease-in-out infinite}",
                ".f1{animation-delay:.28s}.f2{animation-delay:.56s}.f3{animation-delay:.84s}",
                ".f4{animation-delay:1.12s}.f5{animation-delay:1.4s}.f6{animation-delay:1.68s}"
            );
        } else if (ed == 8) {
            k = string.concat(
                k,
                "@keyframes dr{0%,100%{transform:translate(0,0) scale(1)}50%{transform:translate(-34px,22px) scale(1.16)}}",
                ".dr{transform-box:fill-box;transform-origin:center;animation:dr 11s ease-in-out infinite}"
            );
        } else if (ed == 0) {
            // A read head running down the ledger. Two pixels tall and full width, so
            // it registers instantly where a pulsing 8px caption never could.
            k = string.concat(
                k,
                "@keyframes sc{0%{transform:translateY(0)}100%{transform:translateY(268px)}}",
                ".sc{animation:sc 3.6s ease-in-out infinite alternate}",
                // the watermark is the biggest single area on the plate; breathing it
                // moves far more pixels than any caption ever could
                "@keyframes wm{0%,100%{opacity:.02}50%{opacity:.14}}.wm{animation:wm 4.4s ease-in-out infinite}"
            );
        } else if (ed == 7) {
            // Every ticker drifts, staggered, so the whole poster breathes rather than
            // one word fading. Note the combined animation LIST: two classes each
            // setting the `animation` shorthand do not compose — the later rule wins
            // and the first animation is silently dropped.
            k = string.concat(
                k,
                "@keyframes sl{0%,100%{transform:translateX(0)}50%{transform:translateX(34px)}}",
                "@keyframes pu{0%,100%{opacity:.32}50%{opacity:1}}",
                ".mo{animation:sl 4.6s ease-in-out infinite}",
                ".ma{animation:sl 4.6s ease-in-out infinite,pu 2.6s ease-in-out infinite}",
                // delay rules must come after the shorthand, which would otherwise reset them
                ".m1{animation-delay:.22s}.m2{animation-delay:.44s}.m3{animation-delay:.66s}",
                ".m4{animation-delay:.88s}.m5{animation-delay:1.1s}.m6{animation-delay:1.32s}"
            );
        } else if (ed == 1) {
            // The accent band slides across its slot as well as breathing — again as
            // one animation list, not two competing shorthand rules.
            k = string.concat(
                k,
                "@keyframes bd{0%,100%{transform:translateX(0)}50%{transform:translateX(26px)}}",
                "@keyframes pu{0%,100%{opacity:.4}50%{opacity:1}}",
                ".bd{animation:bd 5.4s ease-in-out infinite,pu 2.4s ease-in-out infinite}"
            );
        } else {
            // Mosaic: the grid lights up as a wave rather than one tile at a time.
            k = string.concat(
                k,
                "@keyframes pu{0%,100%{opacity:.3}50%{opacity:1}}.pu{animation:pu 2.6s ease-in-out infinite}",
                ".m1{animation-delay:.2s}.m2{animation-delay:.4s}.m3{animation-delay:.6s}",
                ".m4{animation-delay:.8s}.m5{animation-delay:1s}.m6{animation-delay:1.2s}"
            );
        }

        return string.concat(
            "<style>", k, "@media(prefers-reduced-motion:reduce){*{animation:none!important}.sh{opacity:0}}</style>"
        );
    }

    /// @dev A light sweep across the face, on top of everything. Kept translucent and
    ///      slow: this has to survive being looked at every day without becoming the
    ///      thing you notice, and the numbers underneath must stay readable.
    function _sheen() private pure returns (string memory) {
        return "<g class='sh' style='mix-blend-mode:overlay'>"
            "<rect x='-160' y='-90' width='150' height='680' fill='#FFF' opacity='0.10' transform='rotate(14 250 250)'/>"
            "<rect x='30' y='-90' width='40' height='680' fill='#FFF' opacity='0.06' transform='rotate(14 250 250)'/>"
            "</g>";
    }
}
