// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {ISignatureTransfer} from "./external/ISignatureTransfer.sol";

/// @title IStockPack — full external surface, errors, and events of the StockPack escrow.
/// @notice Single ABI source of truth for tests, the renderer, and the frontend.
interface IStockPack {
    // ─── Errors ───────────────────────────────────────────────────────────────
    error LengthMismatch();
    error EmptyBasket();
    error BasketTooLarge();
    error TokensNotSortedUnique();
    error ZeroAmount();
    error SelfToken();
    error NameLength();
    error FeeOnTransferRejected(address token);
    error NotBasketOwner();
    error NothingToClaim();
    error ZeroRecipient();
    error NonexistentToken();
    error RendererIsLocked();
    error NotArtist();
    error RendererNotContract();

    // ─── Events (dynamic arrays deliberately unindexed) ───────────────────────
    event Packed(uint256 indexed tokenId, address indexed creator, string name, address[] tokens, uint256[] amounts);
    event Unpacked(uint256 indexed tokenId, address indexed redeemer, address indexed recipient);
    event EmergencyUnpacked(uint256 indexed tokenId, address indexed redeemer, address[] tokens, uint256[] amounts);
    event Claimed(address indexed holder, address indexed token, address indexed recipient, uint256 amount);
    event RendererChanged(address indexed renderer);
    event RendererLocked();

    // ─── Mutating ─────────────────────────────────────────────────────────────
    function pack(string calldata name, address[] calldata tokens, uint256[] calldata amounts)
        external
        returns (uint256 tokenId);

    function packWithPermit2(
        string calldata name,
        ISignatureTransfer.PermitBatchTransferFrom calldata permit,
        bytes calldata signature
    ) external returns (uint256 tokenId);

    function unpack(uint256 tokenId) external;
    function unpackTo(uint256 tokenId, address recipient) external;
    function emergencyUnpack(uint256 tokenId) external;
    function claim(address token, address recipient) external;

    function setRenderer(address newRenderer) external;
    function lockRenderer() external;

    // ─── Views ────────────────────────────────────────────────────────────────
    function getBasket(uint256 tokenId) external view returns (address[] memory tokens, uint256[] memory amounts);
    function bundleMeta(uint256 tokenId) external view returns (string memory name, address creator, uint64 sealedAt);
    function claimable(address holder, address token) external view returns (uint256);
    function totalEscrowed(address token) external view returns (uint256);
    function totalMinted() external view returns (uint256);
    function renderer() external view returns (address);
    function artist() external view returns (address);
    function rendererLocked() external view returns (bool);
    function contractURI() external view returns (string memory);
}
