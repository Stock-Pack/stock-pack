// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IStockPack} from "./interfaces/IStockPack.sol";
import {IStockPackRenderer} from "./interfaces/IStockPackRenderer.sol";
import {ISignatureTransfer} from "./interfaces/external/ISignatureTransfer.sol";

/// @title StockPack — immutable basket-wrapper escrow.
/// @notice Deposit a basket of ERC-20s, receive one ERC-721 that is a bearer claim on
///         exactly those balances. The holder can always burn it to withdraw the recorded
///         amounts. No oracles, no fees, no fund-touching admin, no upgrade path.
///
///         Accounting is in RAW token units and never reads live balanceOf for state:
///         donations and rebase noise cannot skew redemptions. Solvency is publicly
///         checkable: for every token, balanceOf(this) >= totalEscrowed(token).
///
/// @dev    The NFT is minted with _mint (no onERC721Received callback, by design — see
///         the Solv double-mint incident). A CONTRACT calling pack() MUST itself be able
///         to call transferFrom/unpackTo, or the escrowed funds are unrecoverable.
///
///         Redemption is strictly ownerOf-only: ERC-721 approvals and operators are
///         deliberately NOT honored on any burn path. Marketplaces need transfers,
///         never redemption — a standing setApprovalForAll must not destroy a basket.
contract StockPack is ERC721, ReentrancyGuardTransient, IStockPack {
    using SafeERC20 for IERC20;

    struct Basket {
        address[] tokens; // strictly ascending — uniqueness and canonical order in one check
        uint256[] amounts; // raw units, measured as received deltas, never user claims
    }

    struct BundleMeta {
        address creator;
        uint64 sealedAt; // block.timestamp — never block.number (approximate L1 block on Nitro)
    }

    uint256 public constant MAX_BASKET_SIZE = 16;
    uint256 public constant MAX_NAME_BYTES = 31; // single-slot short string
    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(uint256 tokenId => Basket) private _baskets;
    mapping(uint256 tokenId => BundleMeta) private _meta;
    mapping(uint256 tokenId => string) private _names;
    /// @dev Populated ONLY by emergencyUnpack; additive across baskets; drained by claim().
    mapping(address holder => mapping(address token => uint256)) private _claimable;
    /// @notice Public liability ledger. balanceOf(this) >= totalEscrowed[token], always.
    mapping(address token => uint256) public totalEscrowed;

    /// @dev Monotonic, burned ids never reused: stale marketplace listings/approvals
    ///      must not attach to a future basket.
    uint256 private _nextTokenId = 1;

    address public renderer;
    address public immutable artist;
    bool public rendererLocked;

    constructor(address renderer_, address artist_) ERC721("StockPack", "PACK") {
        if (renderer_.code.length == 0) revert RendererNotContract();
        renderer = renderer_;
        artist = artist_;
        emit RendererChanged(renderer_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pack
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStockPack
    function pack(string calldata name, address[] calldata tokens, uint256[] calldata amounts)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        uint256 n = tokens.length;
        if (n != amounts.length) revert LengthMismatch();
        _checkShape(n, bytes(name).length);

        address prev;
        for (uint256 i; i < n; ++i) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            _checkEntry(token, amount, prev);
            uint256 before = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            if (IERC20(token).balanceOf(address(this)) - before != amount) revert FeeOnTransferRejected(token);
            prev = token;
        }
        tokenId = _mintBasket(name, tokens, amounts);
    }

    /// @inheritdoc IStockPack
    /// @dev Basket contents derive SOLELY from permit.permitted[] — declaration and
    ///      funding cannot diverge. SignatureTransfer only: one-time, no standing allowances.
    function packWithPermit2(
        string calldata name,
        ISignatureTransfer.PermitBatchTransferFrom calldata permit,
        bytes calldata signature
    ) external nonReentrant returns (uint256 tokenId) {
        uint256 n = permit.permitted.length;
        _checkShape(n, bytes(name).length);

        address[] memory tokens = new address[](n);
        uint256[] memory amounts = new uint256[](n);
        uint256[] memory balBefore = new uint256[](n);
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](n);

        address prev;
        for (uint256 i; i < n; ++i) {
            address token = permit.permitted[i].token;
            uint256 amount = permit.permitted[i].amount;
            _checkEntry(token, amount, prev);
            tokens[i] = token;
            amounts[i] = amount;
            details[i] = ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: amount});
            balBefore[i] = IERC20(token).balanceOf(address(this));
            prev = token;
        }

        PERMIT2.permitTransferFrom(permit, details, msg.sender, signature);

        for (uint256 i; i < n; ++i) {
            if (IERC20(tokens[i]).balanceOf(address(this)) - balBefore[i] != amounts[i]) {
                revert FeeOnTransferRejected(tokens[i]);
            }
        }
        tokenId = _mintBasket(name, tokens, amounts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Unpack / emergency / claim
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStockPack
    function unpack(uint256 tokenId) external {
        unpackTo(tokenId, msg.sender);
    }

    /// @inheritdoc IStockPack
    /// @dev `recipient` lets a blocklisted holder redeem to a clean address.
    function unpackTo(uint256 tokenId, address recipient) public nonReentrant {
        if (recipient == address(0)) revert ZeroRecipient();
        if (ownerOf(tokenId) != msg.sender) revert NotBasketOwner();

        (address[] memory tokens, uint256[] memory amounts) = _closeBasket(tokenId);
        for (uint256 i; i < tokens.length; ++i) {
            totalEscrowed[tokens[i]] -= amounts[i];
        }
        emit Unpacked(tokenId, msg.sender, recipient);

        // Interactions last: a token hook re-entering finds the tokenId already dead.
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransfer(recipient, amounts[i]);
        }
    }

    /// @inheritdoc IStockPack
    /// @dev Escape hatch for frozen constituents (issuer pause/blocklist). Performs ZERO
    ///      external calls, so a poisoned token structurally cannot make it revert. Credits
    ///      per-token pull claims; totalEscrowed is decremented at claim time (the ledger
    ///      equals live baskets + unclaimed emergency rows).
    function emergencyUnpack(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotBasketOwner();

        (address[] memory tokens, uint256[] memory amounts) = _closeBasket(tokenId);
        for (uint256 i; i < tokens.length; ++i) {
            _claimable[msg.sender][tokens[i]] += amounts[i];
        }
        emit EmergencyUnpacked(tokenId, msg.sender, tokens, amounts);
    }

    /// @inheritdoc IStockPack
    /// @dev Best-effort under shortfall: pays min(owed, contract balance) and leaves the
    ///      remainder claimable, so a still-frozen or misbehaving token can never revert
    ///      the claim forever. First-come-first-served if the pool is short.
    function claim(address token, address recipient) external nonReentrant {
        if (recipient == address(0)) revert ZeroRecipient();
        uint256 owed = _claimable[msg.sender][token];
        if (owed == 0) revert NothingToClaim();
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 pay = owed <= bal ? owed : bal;
        if (pay == 0) revert NothingToClaim();

        _claimable[msg.sender][token] = owed - pay;
        totalEscrowed[token] -= pay;
        emit Claimed(msg.sender, token, recipient, pay);

        IERC20(token).safeTransfer(recipient, pay);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Renderer admin — the ONLY admin surface; view-only, cannot reach funds.
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStockPack
    function setRenderer(address newRenderer) external {
        if (msg.sender != artist) revert NotArtist();
        if (rendererLocked) revert RendererIsLocked();
        if (newRenderer.code.length == 0) revert RendererNotContract();
        renderer = newRenderer;
        emit RendererChanged(newRenderer);
    }

    /// @inheritdoc IStockPack
    function lockRenderer() external {
        if (msg.sender != artist) revert NotArtist();
        rendererLocked = true;
        emit RendererLocked();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IStockPack
    function getBasket(uint256 tokenId) external view returns (address[] memory tokens, uint256[] memory amounts) {
        Basket storage b = _baskets[tokenId];
        if (b.tokens.length == 0) revert NonexistentToken();
        return (b.tokens, b.amounts);
    }

    /// @inheritdoc IStockPack
    function bundleMeta(uint256 tokenId) external view returns (string memory name, address creator, uint64 sealedAt) {
        BundleMeta storage m = _meta[tokenId];
        if (m.creator == address(0)) revert NonexistentToken();
        return (_names[tokenId], m.creator, m.sealedAt);
    }

    /// @inheritdoc IStockPack
    function claimable(address holder, address token) external view returns (uint256) {
        return _claimable[holder][token];
    }

    /// @inheritdoc IStockPack
    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return IStockPackRenderer(renderer).tokenURI(tokenId);
    }

    /// @inheritdoc IStockPack
    function contractURI() external view returns (string memory) {
        return IStockPackRenderer(renderer).contractURI();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────────

    function _checkShape(uint256 n, uint256 nameLen) private pure {
        if (n == 0) revert EmptyBasket();
        if (n > MAX_BASKET_SIZE) revert BasketTooLarge();
        if (nameLen == 0 || nameLen > MAX_NAME_BYTES) revert NameLength();
    }

    /// @dev `token > prev` enforces strict ascension, which simultaneously rejects
    ///      duplicates, guarantees canonical order, and (since prev starts at 0)
    ///      rejects address(0).
    function _checkEntry(address token, uint256 amount, address prev) private view {
        if (token <= prev) revert TokensNotSortedUnique();
        if (amount == 0) revert ZeroAmount();
        if (token == address(this)) revert SelfToken();
    }

    /// @dev All storage effects and the Packed event land before _mint. _mint (not
    ///      _safeMint): no receiver callback may take control mid-mint.
    function _mintBasket(string calldata name, address[] memory tokens, uint256[] memory amounts)
        private
        returns (uint256 tokenId)
    {
        tokenId = _nextTokenId++;
        Basket storage b = _baskets[tokenId];
        b.tokens = tokens;
        b.amounts = amounts;
        _meta[tokenId] = BundleMeta({creator: msg.sender, sealedAt: uint64(block.timestamp)});
        _names[tokenId] = name;
        for (uint256 i; i < tokens.length; ++i) {
            totalEscrowed[tokens[i]] += amounts[i];
        }
        emit Packed(tokenId, msg.sender, name, tokens, amounts);
        _mint(msg.sender, tokenId);
    }

    /// @dev Shared teardown: copy basket to memory, delete every storage row, burn the
    ///      NFT. Deleted storage doubles as reentrancy defense — strict CEI.
    function _closeBasket(uint256 tokenId) private returns (address[] memory tokens, uint256[] memory amounts) {
        Basket storage b = _baskets[tokenId];
        tokens = b.tokens;
        amounts = b.amounts;
        delete _baskets[tokenId];
        delete _meta[tokenId];
        delete _names[tokenId];
        _burn(tokenId);
    }
}
