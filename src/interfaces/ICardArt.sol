// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

/// @title ICardArt — the generative artwork surface the renderer delegates to.
/// @notice Split out of StockPackRenderer purely for EIP-170 headroom: six editions
///         of SVG template do not fit alongside the JSON metadata layer. Pure, view-only,
///         and reachable only through the renderer, which is itself fund-blind.
interface ICardArt {
    /// @param name        bundle name, already ASCII-sanitized (NOT yet XML-escaped)
    /// @param tokenId     0 for a pre-mint preview
    /// @param sealedAt    0 for a pre-mint preview
    /// @param symbols     sanitized ticker strings, one per constituent
    /// @param amountStrs  preformatted display amounts, parallel to `symbols`
    /// @param total       full constituent count (editions cap the rows they draw)
    /// @param seed        keccak(name, creator) — every trait derives from this
    /// @param preview     true renders the unsealed footer and suppresses the serial
    struct Card {
        string name;
        uint256 tokenId;
        uint64 sealedAt;
        string[] symbols;
        string[] amountStrs;
        uint256 total;
        uint256 seed;
        bool preview;
    }

    /// @notice The full 350x500 SVG document for one card.
    function render(Card calldata c) external pure returns (string memory);

    /// @notice Trait indices for the metadata layer, derived from the same seed
    ///         the artwork uses. Kept here so art and attributes can never disagree.
    function traits(uint256 seed) external pure returns (uint256 edition, uint256 palette, uint256 finish);

    /// @notice Human-readable trait names for `attributes` in the JSON, plus the
    ///         rarity tier implied by the combination (Common / Uncommon / Rare /
    ///         Mythic). Tier is derived here rather than stored so it can never drift
    ///         from the artwork the same seed produces.
    function traitNames(uint256 edition, uint256 palette, uint256 finish)
        external
        pure
        returns (string memory editionName, string memory paletteName, string memory finishName, string memory tierName);
}
