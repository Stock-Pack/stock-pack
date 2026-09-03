// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Adversarial ERC-20 flavors (d-xo/weird-erc20 style), consolidated in one file.
///         Used to prove StockPack either safely handles or verifiably rejects each quirk.

contract BaseMockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) public virtual {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// @dev Skims `feeBps` of every transfer to a sink — must be REJECTED at pack().
contract FeeOnTransferToken is BaseMockERC20 {
    uint256 public feeBps;

    constructor(uint256 feeBps_) BaseMockERC20("Fee Token", "FEE") {
        feeBps = feeBps_;
    }

    function _move(address from, address to, uint256 amount) internal override {
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        balanceOf[address(0xFEE)] += fee;
    }
}

/// @dev Shares-based rebasing token (xStocks/stETH semantics): admin moves `factor`,
///      every balance scales. Passes the pack() delta check at factor=1e18, then a
///      downward rebase under-collateralizes the commingled pool.
contract RebasingToken {
    string public name = "Rebasing Token";
    string public symbol = "REB";
    uint8 public decimals = 18;
    uint256 public factor = 1e18; // balance = shares * factor / 1e18
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function setFactor(uint256 f) external {
        factor = f;
    }

    function totalSupply() external view returns (uint256) {
        return totalShares * factor / 1e18;
    }

    function balanceOf(address a) public view returns (uint256) {
        return sharesOf[a] * factor / 1e18;
    }

    function mint(address to, uint256 amount) external {
        uint256 sh = amount * 1e18 / factor;
        sharesOf[to] += sh;
        totalShares += sh;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal {
        uint256 sh = amount * 1e18 / factor;
        require(sharesOf[from] >= sh, "REB: balance");
        sharesOf[from] -= sh;
        sharesOf[to] += sh;
    }
}

/// @dev Issuer blocklist (USDC/USDT-style; the Robinhood Stock Token freeze scenario).
contract BlocklistToken is BaseMockERC20 {
    mapping(address => bool) public blocked;

    constructor() BaseMockERC20("Blocklist Token", "BLK") {}

    function setBlocked(address who, bool isBlocked) external {
        blocked[who] = isBlocked;
    }

    function _move(address from, address to, uint256 amount) internal override {
        require(!blocked[from] && !blocked[to], "BLK: blocked");
        super._move(from, to, amount);
    }
}

/// @dev Issuer pause (Robinhood Stock Tokens are pausable beacon proxies).
contract PausableToken is BaseMockERC20 {
    bool public paused;

    constructor() BaseMockERC20("Pausable Token", "PAU") {}

    function setPaused(bool p) external {
        paused = p;
    }

    function _move(address from, address to, uint256 amount) internal override {
        require(!paused, "PAU: paused");
        super._move(from, to, amount);
    }
}

/// @dev USDT-style: transfer/transferFrom/approve return NOTHING. SafeERC20 must cope.
contract NoReturnToken {
    string public name = "No Return Token";
    string public symbol = "NRT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// @dev Reverts on zero-amount transfers (some tokens do). StockPack never transfers 0.
contract RevertOnZeroToken is BaseMockERC20 {
    constructor() BaseMockERC20("Revert On Zero", "ROZ") {}

    function _move(address from, address to, uint256 amount) internal override {
        require(amount != 0, "ROZ: zero");
        super._move(from, to, amount);
    }
}

/// @dev Armed transfer hook that attempts to re-enter an arbitrary target call
///      (pack/unpack/claim). Records whether the reentry succeeded for assertions.
contract ReentrantToken is BaseMockERC20 {
    address public target;
    bytes public payload;
    bool public armed;
    bool public lastReentrySucceeded;

    constructor() BaseMockERC20("Reentrant Token", "REE") {}

    function arm(address target_, bytes calldata payload_) external {
        target = target_;
        payload = payload_;
        armed = true;
    }

    function disarm() external {
        armed = false;
    }

    function _move(address from, address to, uint256 amount) internal override {
        super._move(from, to, amount);
        if (armed) {
            armed = false; // one shot — avoid infinite loops
            (bool ok,) = target.call(payload);
            lastReentrySucceeded = ok;
        }
    }
}

/// @dev A contract that calls pack() but has no way to transfer or unpack the NFT it
///      receives — documents the intended stuck-by-design behavior of _mint.
contract NaivePacker {
    function doPack(address stockPack, string calldata name, address[] calldata tokens, uint256[] calldata amounts)
        external
        returns (uint256)
    {
        (bool ok, bytes memory ret) =
            stockPack.call(abi.encodeWithSignature("pack(string,address[],uint256[])", name, tokens, amounts));
        require(ok, "pack failed");
        return abi.decode(ret, (uint256));
    }

    function approveToken(address token, address spender) external {
        (bool ok,) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, type(uint256).max));
        require(ok, "approve failed");
    }
}
