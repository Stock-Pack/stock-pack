# Rarity

Every trait is drawn from one number — `keccak256(bundle name, creator address)` — using
fixed weights written into the contract. The odds below are **not estimates**: they are
counted directly out of the contract's own trait function across all 256 possible values
of each seed byte, which is exhaustive rather than a sample. Reproduce them yourself
with `forge script script/RarityTable.s.sol`.

The weights are immutable for as long as the artwork contract is the one the escrow
points at. They cannot be tuned after the fact.

Every trait below links to a reference card rendered straight out of the contract. The
files live in `web/public/art/{editions,palettes,finishes}/` and are served at
`/art/...`, so a page can embed them directly — they are real output, not mockups.
Regenerate them any time with `forge script script/RenderDocs.s.sol`.

---

## Tier

Tier is **derived**, not rolled separately. Points come from the scarcity of what you
actually got — the rarer editions, the rare palette band and the rare finishes each
contribute — so the badge can never disagree with the picture.

| Tier | Share of all cards | Roughly |
| --- | --- | --- |
| Common | 53.38% | 1 in 1.9 |
| Uncommon | 36.86% | 1 in 2.7 |
| Rare | 8.85% | 1 in 11 |
| **Mythic** | **0.91%** | **1 in 110** |

How the points are scored:

| Source | Points |
| --- | --- |
| Guilloche or Aurora edition | +3 |
| Monolith or Splitflap edition | +2 |
| Orbit, Terminal or Mosaic edition | +1 |
| Any rare palette (Gilt, Glacier, Vapor, Ember) | +2 |
| Engraved finish | +3 |
| Gilded finish | +2 |
| Foil finish | +1 |

`0–1 → Common · 2–3 → Uncommon · 4–5 → Rare · 6+ → Mythic`

---

## Editions

The composition. Ten of them, weighted so the house style is common and the engraved
banknote is not.

| Edition | Odds | 1 in | What it is |
| --- | --- | --- | --- |
| [Ledger](/art/editions/ledger.svg) | 17.19% | 5.8 | Bearer-instrument plate: ruled table, watermark serial, share-of-basket bar |
| [Strata](/art/editions/strata.svg) | 14.84% | 6.7 | One colour band per position, height driven by that position's own hash |
| [Tape](/art/editions/tape.svg) | 13.28% | 7.5 | The holdings as a ticker running the full card, two rows struck on accent bars |
| [Mosaic](/art/editions/mosaic.svg) | 12.50% | 8.0 | A tiled bento field; the last tile of each row stretches so the grid never gaps |
| [Terminal](/art/editions/terminal.svg) | 10.94% | 9.1 | The `pack()` call as a console transcript, prompt and cursor included |
| [Orbit](/art/editions/orbit.svg) | 10.16% | 9.8 | Positions as satellites on a 60-tick dial around the card's own serial |
| [Splitflap](/art/editions/splitflap.svg) | 8.59% | 11.6 | An airport departure board, one flap cell per character |
| [Monolith](/art/editions/monolith.svg) | 6.25% | 16.0 | Tickers at poster scale, cropped by the frame |
| [Aurora](/art/editions/aurora.svg) | 3.91% | 25.6 | Stacked gradient colour fields behind a glass data panel |
| **[Guilloche](/art/editions/guilloche.svg)** | **2.34%** | **42.7** | Seven interfering sine-modulated rings — a banknote rosette |

Guilloche's petal count is derived from your position count, so the engraving is
literally a portrait of the basket size.

---

## Palettes

Eight common palettes at 10.55% each, and a rare band of four at 3.91% each. A rare
palette on its own is worth +2 tier points.

| Palette | Odds | 1 in | |
| --- | --- | --- | --- |
| [Obsidian](/art/palettes/obsidian.svg) | 10.55% | 9.5 | near-black, warm white, amber |
| [Bone](/art/palettes/bone.svg) | 10.55% | 9.5 | bone white, ink, signal red |
| [Vellum](/art/palettes/vellum.svg) | 10.55% | 9.5 | aged cream, forest green |
| [Cobalt](/art/palettes/cobalt.svg) | 10.55% | 9.5 | deep navy, bright blue |
| [Oxide](/art/palettes/oxide.svg) | 10.55% | 9.5 | rust brown, burnt orange |
| [Chlorophyll](/art/palettes/chlorophyll.svg) | 10.55% | 9.5 | dark green, acid green |
| [Ash](/art/palettes/ash.svg) | 10.55% | 9.5 | neutral grey, hot orange |
| [Plum](/art/palettes/plum.svg) | 10.55% | 9.5 | deep purple, magenta |
| **[Gilt](/art/palettes/gilt.svg)** | **3.91%** | **25.6** | black and gold |
| **[Glacier](/art/palettes/glacier.svg)** | **3.91%** | **25.6** | ice white, arctic blue |
| **[Vapor](/art/palettes/vapor.svg)** | **3.91%** | **25.6** | violet black, cyan |
| **[Ember](/art/palettes/ember.svg)** | **3.91%** | **25.6** | charcoal, hot red |

---

## Finishes

The surface treatment. The two rare finishes are **border metalwork, not overlays** —
they are deliberately built so they never cross the data. A card's numbers are just as
readable Engraved as Matte.

| Finish | Odds | 1 in | |
| --- | --- | --- | --- |
| [Matte](/art/finishes/matte.svg) | 46.88% | 2.1 | no treatment |
| [Etched](/art/finishes/etched.svg) | 23.44% | 4.3 | fine 45° hatch across the whole card |
| [Foil](/art/finishes/foil.svg) | 17.19% | 5.8 | crisp diagonal sheen sweeps |
| **[Gilded](/art/finishes/gilded.svg)** | **9.38%** | **10.7** | double keyline and corner ticks struck in the accent |
| **[Engraved](/art/finishes/engraved.svg)** | **3.13%** | **32.0** | a guilloche wave run around all four borders, over a double keyline |

---

## Chasing specific cards

The three traits are drawn from independent bytes of the seed, so combined odds
multiply.

| Combination | Odds | 1 in |
| --- | --- | --- |
| Any Mythic card | 0.909% | 110 |
| Guilloche, any palette or finish | 2.34% | 43 |
| Engraved, any edition or palette | 3.13% | 32 |
| Guilloche + Engraved | 0.073% | 1,365 |
| Guilloche + any rare palette + Engraved | 0.0114% | 8,738 |
| Guilloche + one named rare palette + Engraved | 0.0029% | **34,953** |

The last row — say Guilloche on Gilt with an Engraved border — is the rarest single card
the contract can produce.

Remember that the seed is `keccak256(name, creator)` — the **bundle name is the only
input you control**. Rename before sealing and the whole card rerolls, live in the
preview. After minting it is fixed forever.
