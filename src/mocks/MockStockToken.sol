// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockStockToken — demo tokenized stock with a public faucet.
/// @notice Lives in src/ (not test/) because the dApp faucet calls it on-chain. Mirrors
///         the ERC-8056 "Scaled UI Amount" surface of real Robinhood Stock Tokens
///         (raw balances never rebase; corporate actions move uiMultiplier) so testnet
///         rehearses real-token display semantics.
contract MockStockToken is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 100e18;
    uint256 public constant FAUCET_COOLDOWN = 1 hours;
    uint256 public constant MAX_MINT = 1_000e18;

    address public immutable admin; // demo-only: bumps uiMultiplier to simulate corporate actions
    uint8 private immutable _decimals;

    /// @dev ERC-8056: shares = raw balance × uiMultiplier / 1e18. Display-only.
    uint256 public uiMultiplier = 1e18;
    mapping(address => uint256) public lastFaucetAt;

    event UIMultiplierUpdated(uint256 newMultiplier);

    error FaucetCooldown();
    error MintTooLarge();
    error NotAdmin();

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        admin = msg.sender;
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function faucet() external {
        if (block.timestamp < lastFaucetAt[msg.sender] + FAUCET_COOLDOWN) revert FaucetCooldown();
        lastFaucetAt[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    function mint(address to, uint256 amount) external {
        if (amount > MAX_MINT) revert MintTooLarge();
        _mint(to, amount);
    }

    // ─── ERC-8056-style display surface ──────────────────────────────────────

    function balanceOfUI(address account) external view returns (uint256) {
        return balanceOf(account) * uiMultiplier / 1e18;
    }

    function totalSupplyUI() external view returns (uint256) {
        return totalSupply() * uiMultiplier / 1e18;
    }

    /// @notice Simulates a corporate action (dividend/split). Raw balances untouched.
    function setUIMultiplier(uint256 newMultiplier) external {
        if (msg.sender != admin) revert NotAdmin();
        uiMultiplier = newMultiplier;
        emit UIMultiplierUpdated(newMultiplier);
    }
}
