# StockPack — Product Overview (public copy source)

> Audience: anyone. This is the plain-language explanation of what StockPack is, how it works, and
> why it is safe to trust. It contains no code, no infrastructure details, and nothing sensitive —
> lift freely from it for the landing page, Twitter/X threads, docs, pitch decks, and press.

---

## The one-liner

**StockPack is the on-chain ownership layer for tokenized equity — real-world assets wrapped into one
tradable card you can always unwrap.**

Stock tokens are the *asset layer*: real equity brought on-chain as ordinary tokens. StockPack is the
*layer on top* — one object that carries a whole portfolio, trades anywhere, and unwraps to the exact
underlying at any moment.

Pick the stocks and coins you want, choose the amounts, give the bundle a name, and seal it.
You get one NFT — a portfolio card — that holds exactly those assets. Send it, sell it, or keep it.
Whoever holds the card can unwrap it at any moment and receive every underlying token back, in a single transaction.

---

## The problem

Real-world assets (RWAs) are arriving on-chain fast, and tokenized stocks are the clearest example.
But they arrive as *individual positions*, and a portfolio is still not a thing you can hold.
If you want to hand someone "1 NVDA + 1 AAPL + 1 MSFT", you make three transfers.
If you want to sell that portfolio, you list three assets separately.
If you want to gift, split, or trade a themed basket, there is no single object that *is* the basket.

Existing "index" or "wrapper" products solve this with managers, oracles, fees, and a company in the middle
that can pause, reprice, or change the rules. That is the opposite of what a self-custodied portfolio should be.

---

## The solution

StockPack is a **basket wrapper with no one in the middle.**

- **You deposit, you get one card.** Up to 16 different tokens, any amounts, any mix of tokenized stocks and coins.
- **The card is a bearer claim.** It is worth exactly what is inside it — not an estimate, not a price feed, the literal tokens.
- **Anyone holding the card can unwrap it.** One click, one transaction, and every token lands in their wallet.
- **Nobody can interfere.** No admin, no owner, no pause button, no fee switch, no upgrade. The rules are frozen in the contract forever.

Think of it as vacuum-sealing a portfolio. The seal is transparent — everyone can see exactly what is inside —
and only the person holding it can break it open.

---

## In plain English

You hold tokenized stocks in your wallet — some NVDA, some AAPL, some TSLA — each sitting there as a
separate position. StockPack lets you put any mix of them into one sealed package and hands you a single
item back. Think of it as putting share certificates into a locked box and getting one claim ticket. The
ticket lives in your wallet, it has a name you choose, and it comes with its own artwork. What is inside is
fixed the moment you seal it.

Why you would want that: your whole portfolio becomes one thing you can move. Instead of selling seven
positions one at a time, you list the package and whoever buys it gets everything inside, in one go. You can
send it to someone as a single transfer, or hold it as a snapshot of what you owned on a particular day. And
since every package looks different and carries its name and contents on the face of it, it is something you
can actually show people — not a row in a spreadsheet.

The part that matters: you can open the package whenever you like and get your exact shares back. Not a cash
payout, not today's price — the same tokens you put in, down to the decimal. Nobody can stop you doing it,
including us. There is no fee, no manager deciding what goes in, no price feed that could glitch and misprice
your holdings, and no admin key that can reach inside and take anything. Those are not promises we are
making — they are limits written into the contract, and anyone can check them.

---

## How it works (in three steps)

**1. Pack.**
Choose your tokens and amounts, name the bundle ("Big Tech", "My AI Basket", "Dividend Starter"), and seal it.
The tokens move into a vault contract and you receive one portfolio card in return. The card's artwork,
name, and contents are generated fully on-chain — no server, no image host, no link that can rot.

**2. Hold, send, or trade.**
The card is a standard NFT. It shows up in your wallet like any other collectible, with a description
that spells out exactly what it is worth ("Worth exactly 12 AMZN + 0.1 MSFT + 13 NVDA"). You can send it to
a friend, list it on a marketplace, or trade it peer-to-peer. The contents never change while it travels.

**3. Unpack.**
Whoever holds the card presses Unpack. The card is burned and every token inside is delivered to their
wallet in one transaction. The amounts are exactly what was sealed — down to the last unit.

---

## Why you can trust it

**100% backed, publicly provable.**
For every token, the vault's balance is always at least the total it owes to all cards. That number is a
public figure on the blockchain — anyone can check it at any time. There is no "trust us" step.

**Redeemable only by the holder.**
Only the wallet that owns the card can unwrap it. Marketplace listings and approvals can never be used to
drain a bundle — a lesson learned from real incidents elsewhere in the NFT space, and designed out from day one.

**Frozen at mint.**
Once sealed, a bundle cannot be topped up, partially withdrawn, or edited by anyone. What a buyer sees
is exactly what they get.

**No fund-touching admin. Ever.**
There is no owner key that can pause withdrawals, sweep balances, take a cut, or upgrade the logic.
The single administrative capability in the entire system is the ability to update how the card *artwork*
is drawn — a purely visual setting that cannot reach funds and that is permanently locked shortly after launch.

**Works without us.**
The website is a convenience, not a requirement. If the site ever went offline, every card could still be
unwrapped directly on-chain through any wallet or block explorer. Your portfolio never depends on a company staying alive.

**Built for the messy real world.**
Tokenized stocks can be paused or restricted by their issuers. StockPack has a built-in emergency path:
if one token in a bundle is frozen, you can still break the seal and claim every other token immediately,
and collect the frozen one the moment it thaws. One bad token never traps the rest.

**Tested like it matters.**
The contracts are covered by unit tests, fuzz tests, adversarial-token tests (fee-on-transfer, rebasing,
pausable, blocklisting, reentrant, and malformed tokens), and protocol-wide invariants — including one that
literally unwraps every live bundle after a randomized simulation and checks that each holder receives
exactly what was sealed. They have also been exercised against the real tokenized stocks on Robinhood Chain.
An independent security audit has been completed, and legal counsel has reviewed the wrap-and-trade model.

---

## The card itself

Every bundle mints a card whose artwork is generated **on-chain, at read time** — no server, no image
host, nothing that can rot. The look is drawn from the bundle's name and its creator, so the name you
choose is the one thing you control: rename before sealing and the whole card rerolls, live in the preview.

There are **ten compositions** — a ruled ledger, colour bands, a running ticker tape, a tiled mosaic, a
terminal transcript, an orrery of satellites, a departure board, poster-scale type, gradient fields, and a
banknote rosette — crossed with **twelve palettes** and **five finishes**. A **Tier** (Common, Uncommon,
Rare, Mythic) is derived from the combination rather than rolled separately, so the badge can never
disagree with the picture.

The cards move. Each composition animates the way its own geometry suggests, and because the animation
lives inside the image itself, a card is alive in a wallet or on a marketplace — not only on our site.

Full odds are published and counted directly out of the contract, not restated from intent.

---

## What makes it different

| | Typical index / wrapper products | StockPack |
|---|---|---|
| Who controls the assets | A manager or company | Only the card holder |
| How value is determined | Price oracles, NAV calculations | The literal tokens inside |
| Can it be paused or changed | Usually yes | No — no admin exists |
| Fees | Management / performance fees | None |
| If the company disappears | Assets may be stuck | Unwrap directly on-chain, forever |
| Artwork and metadata | Hosted on a server | Generated on-chain, permanent |

---

## Who it's for

- **Gifters and educators** — hand someone a "starter portfolio" as a single object.
- **Traders** — buy and sell whole themed baskets in one listing instead of juggling many positions.
- **Collectors and builders** — create named, dated, visually distinct portfolio cards ("Sealed 2026-09-02").
- **Anyone who wants a portfolio they can hold in their hand** — one card, exact contents, always redeemable.

---

## Settled on an Arbitrum Layer 2

StockPack lives on Robinhood Chain, an Arbitrum Orbit Layer 2 where real tokenized stocks and coins trade
on-chain. That is the settlement layer: fast, cheap, and public. StockPack wraps the same standard tokens
that already exist there — it does not issue, price, or custody anything on your behalf beyond holding
sealed baskets in a transparent vault.

Corporate actions on tokenized stocks (splits, dividends) are reflected by the token issuer's own mechanism,
so a sealed bundle continues to track the real-world value of its shares while it is packed.

---

## Frequently asked questions

**Is the card actually worth the stocks inside?**
Yes — it is a direct claim on them. The card's on-chain description states the exact contents,
and unwrapping delivers precisely those tokens. There is no price feed or estimate involved.

**Can someone drain my bundle if I list it on a marketplace?**
No. Listing requires a transfer approval, and StockPack deliberately ignores approvals for unwrapping.
Only the actual owner of the card can break the seal.

**What if the website goes down?**
Nothing changes for you. The vault is a public contract on the blockchain. You can unwrap through any
wallet, block explorer, or third-party interface, with or without our site.

**Can I add to or partially withdraw from a bundle?**
No — bundles are frozen at creation. To change a portfolio, unwrap and re-pack. This is what makes a
card trustworthy to a buyer: what they verify cannot change before they receive it.

**Are there fees?**
StockPack charges nothing. You pay only the network's normal transaction gas.

**What happens if one of my tokens gets frozen by its issuer?**
Use the emergency unpack. It breaks the seal without touching the frozen token, lets you claim every
other token immediately, and keeps the frozen one claimable for whenever it becomes transferable again.

**Who can change the rules?**
No one. The contract has no owner and no upgrade mechanism. The only adjustable setting is the card
artwork style, which cannot affect funds and is permanently locked after launch.

**Where does the artwork live?**
On-chain. Every card's image, name, contents, and sealing date are generated by the contract itself.
No server, no IPFS link, nothing that can disappear.

---

## Ready-to-use copy

### Taglines
- The on-chain ownership layer for tokenized equity.
- Real-world assets, wrapped into one composable primitive.
- Your portfolio, sealed in a card.
- One card. Exact contents. Always redeemable.
- Bundle stocks. Trade the bundle. Unwrap anytime.
- A portfolio you can hold in your hand — and open whenever you want.
- No manager. No oracle. No fees. Just your tokens, sealed and provable.

### Short description (app stores, link previews, bios)
The ownership layer for tokenized equity. StockPack seals a basket of real-world assets into a single card
that is 100% backed, tradable, and redeemable by whoever holds it — settled on an Arbitrum Layer 2, with no
admin, no fees, and no middleman.

### Landing page hero
**Tokenized stock baskets, sealed on-chain.**
Pick your stocks and coins, seal them into one NFT, and trade or gift the whole basket at once.
Whoever holds the card can unwrap it anytime and get every token back — exactly, provably, and without asking anyone.

### Feature blocks
- **100% backed.** Every card is a direct claim on real tokens held in a transparent vault. Solvency is public.
- **Unwrap anytime.** One click returns every token inside to your wallet in a single transaction.
- **Tradable.** A standard NFT with on-chain artwork and per-stock traits — list it, send it, swap it.
- **No admin over funds.** No owner, no pause, no fees, no upgrades. The rules are frozen forever.
- **Survives anything.** Works even if our website disappears. Built-in emergency path if an issuer freezes a token.
- **Battle-tested.** Fuzzed, invariant-tested, adversarial-token-tested, audited, and legally reviewed.

### Twitter / X thread (draft)
1/ Tokenized stocks are on-chain now. But a *portfolio* still isn't a thing you can hold, send, or sell as one object. StockPack fixes that. 🧵

2/ Pick your stocks and coins. Set amounts. Name the bundle. Seal it. You get one NFT card that holds exactly those tokens — no oracle, no estimate, the literal assets.

3/ The card is a bearer claim. Whoever holds it can unwrap it in one click and receive every token inside. Exactly what was sealed. Every time.

4/ There is no admin. No owner key, no pause, no fees, no upgrades. Nobody — including us — can touch what's in a card.

5/ Backing is public. For every token, the vault's balance is always ≥ what it owes. Anyone can verify this on-chain, anytime.

6/ Marketplace-safe by design. Listing a card requires an approval — and StockPack deliberately ignores approvals for unwrapping. Only the real owner can break the seal.

7/ It works without us. Our site is a convenience. If it vanished tomorrow, every card could still be unwrapped straight from the blockchain.

8/ Real-world resilient. If an issuer freezes one stock, the emergency path lets you claim everything else immediately and collect the frozen one when it thaws.

9/ On-chain art, on-chain metadata. Every card's image, contents, and sealing date are generated by the contract. Nothing to rot, nothing to lose.

10/ Fuzzed, invariant-tested, tested against hostile tokens, audited, and legally reviewed. Live on Robinhood Chain, an Arbitrum Layer 2.

### Single-tweet versions
- Seal a basket of tokenized stocks into one NFT. Trade it. Gift it. Unwrap it anytime — exactly, provably, with no admin in the way. That's StockPack.
- Your portfolio, as a card. 100% backed. Redeemable by the holder. Zero fees, zero admin, zero middlemen.
- What if "1 NVDA + 1 AAPL + 1 MSFT" was one thing you could hold? Now it is.

---

## Roadmap (public-safe)

- ✅ Testnet live with a full create → trade → unwrap flow
- ✅ Independent security audit completed
- ✅ Legal review of the wrap-and-trade model completed
- ✅ **Mainnet live on Robinhood Chain** with real tokenized stocks and coins
- ✅ Ten generative card editions, animated on-chain, with published rarity
- ⏳ Marketplace listings with per-stock filters
- ⏳ Rich social previews for every card
