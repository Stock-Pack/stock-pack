# The StockPack card

Every StockPack bundle is an ERC-721 whose artwork is **generated on-chain, at read
time**. Nothing is uploaded, pinned or stored on a server: when a marketplace asks the
contract for `tokenURI(id)`, the contract builds the entire SVG and its metadata from
scratch and hands it back. There is no image file anywhere. If Robinhood Chain is
running, your card renders.

## What decides how your card looks

One number, called the **seed**:

```
seed = keccak256(bundle name, creator address)
```

That seed selects the **edition** (the composition), the **palette** (the colours) and
the **finish** (the surface treatment). The basket itself decides the rest — how many
positions you packed changes the layout, and each position's own hash drives its band
height, its tile, its place on the dial.

Three consequences worth knowing:

- **The preview is the card.** The artwork shown before you mint is generated from the
  same seed as the minted token. What you see on the create page is exactly what you
  get — not an approximation.
- **The token id is not an input.** Two people who pack the same basket name from the
  same wallet get the same look, whether they mint first or thousandth.
- **Changing the name changes the card.** The name is part of the seed, so it is the
  one lever you control. If you want a different edition, rename the bundle before
  sealing and watch the preview change.

## Every card is readable

Whatever the edition, the card always states what it holds: the ticker and the exact
escrowed amount of every position it can fit, the total count, the seal date, and the
`100% REDEEMABLE` line. Editions cap how many rows they draw — a departure board cannot
show sixteen — but a card that caps its rows always says so, either by naming the
remainder (`+6 more`) or by printing the true position count. **No card ever hides part
of the basket.**

The art is decoration on top of a financial instrument, never a substitute for it. The
authoritative record is always `getBasket(tokenId)` on-chain.

## Where the art lives

The artwork contract is separate from the escrow that holds your tokens, and it is
**view-only** — it can read nothing and move nothing. It provably cannot touch escrowed
funds. The escrow's `artist` key can point the metadata at a new artwork contract until
`lockRenderer()` is called, after which the pointer is frozen permanently.

See **[Rarity](./nft-rarity.md)** for the full trait tables and odds.
