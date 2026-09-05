# StockPack brand

The public kit is served from `web/public/brand/` and documented at `/brand` on the site.
The header and footer draw the lockup inline from `web/components/Logo.tsx`.

## Sources

`source/` holds the five reference images the identity was supplied as (JPEG, 800–1280 px).
They are the visual reference, not the shipping files: the mark in them is hand-drawn and
its four blades differ from one another by up to 25 px, and the lockup is cream on white.
Everything in the kit was rebuilt as vector from these references.

## The mark

Four blades turning around an amber diamond, exactly 4-fold symmetric. On a 1024 canvas
centred at (512, 512), the right blade is the polygon below and the other three are its
90° rotations. All edges are axis-aligned or at 45°.

| parameter | value | meaning |
|---|---|---|
| R | 440 | outer apothem — the octagon's flat edges sit at ±440 |
| E | 150 | half-length of each flat edge (blade thickness = E·√2 ≈ 212) |
| D1 | 190 | outer diagonal run from the flat edge to the blade's outer corner |
| W1 | 116 | the axis-aligned step at the blade's outer corner |
| D2 | 190 | the perpendicular cut that ends the blade |
| W2 | 2·D2 + W1 − 2·E = 196 | the inner step; this value closes the flat edge symmetrically |
| diamond | half-diagonal 128 | a square rotated 45°, centred |

Right blade, relative to centre: (R,−E) → (R−D1, −E−D1) → (R−D1−W1, −E−D1) →
(R−D1−W1−D2, −E−D1+D2) → (R−D1−W1−D2+W2, −E−D1+D2) → (R, E). The channel between
blades is 59 units wide; the favicon (`web/app/icon.svg`) widens it with a plate-coloured
stroke so it survives 16 px.

## The lockup

Units: wordmark cap height = 100, baseline y = 0.

- Wordmark: **Playfair Display 700**, "StockPack", natural kerning, as outlines. Width 673.
- Mark: 182 tall (octagon extent), centred on the cap band, 57 before the wordmark.
- Full stop: amber circle, r = 9, sitting on the baseline, 32 after the wordmark.

## Colour

| name | hex | use |
|---|---|---|
| Ink | `#0A0A0A` | brand black, every dark ground |
| Cream | `#F4F0E5` | the mark and wordmark on dark |
| Amber | `#F1A93B` | the diamond and the full stop only |

On the site the inline lockup uses `currentColor` and `var(--color-accent)` so it follows
the theme tokens rather than these fixed values.

## Files

| file | what |
|---|---|
| `web/public/brand/stockpack-mark-{cream,ink}.svg` + `-1024.png` | mark, transparent |
| `web/public/brand/stockpack-mark-{dark,white}-1024.png` | mark on a plate |
| `web/public/brand/stockpack-avatar-800.png` | mark on black with a hairline ring, for profile pictures |
| `web/public/brand/stockpack-lockup-{cream,ink}.svg` + `-2400.png` | lockup, transparent |
| `web/public/brand/stockpack-lockup-{dark,white}-2400.png` | lockup on a plate |
| `web/public/brand/stockpack-social-1200x630.jpg` | Open Graph card (also `web/app/opengraph-image.jpg`) |
| `web/public/brand/stockpack-banner-portfolio-1200x675.jpg` | 16:9 campaign banner, as supplied |
| `web/public/brand/stockpack-banner-header-1280x427.jpg` | 3:1 profile header, as supplied |
| `web/app/icon.svg`, `web/app/apple-icon.png` | favicon and touch icon |
| `web/public/og-mark.png`, `web/public/logo*.svg`, `docs/assets/avatar.png`, `docs/assets/logo.png` | older paths, kept working with the new mark |
