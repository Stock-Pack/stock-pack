// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

/// @title IStockPackRenderer — the view-only metadata surface StockPack delegates to.
interface IStockPackRenderer {
    error NotArtist();
    error InvalidBaseUrl();

    event BaseUrlUpdated(string baseUrl);

    /// @notice Origin embedded in every card's `external_url` / redeem hint (no trailing slash).
    function baseUrl() external view returns (string memory);

    /// @notice Re-points metadata at a new dApp origin. Callable by the escrow's `artist`
    ///         forever — lockRenderer() freezes the renderer pointer, not this string.
    function setBaseUrl(string calldata newBaseUrl) external;

    function tokenURI(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);

    /// @notice Renders the card for a not-yet-minted basket. `creator` feeds the
    ///         deterministic accent hue (keccak(name, creator)) so the preview is
    ///         color-identical to the minted card; the footer reads PREVIEW · UNSEALED.
    function previewSVG(address[] calldata tokens, uint256[] calldata amounts, string calldata name, address creator)
        external
        view
        returns (string memory);
}
