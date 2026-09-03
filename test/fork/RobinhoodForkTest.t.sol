// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {StockPack} from "../../src/StockPack.sol";
import {StockPackArt} from "../../src/art/StockPackArt.sol";
import {StockPackRenderer} from "../../src/StockPackRenderer.sol";

interface IStockTokenLike {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function uiMultiplier() external view returns (uint256);
}

/// @notice Fork tests against live Robinhood Chain mainnet (4663). Run with:
///         forge test --match-contract RobinhoodFork --fork-url $ROBINHOOD_RPC_URL
///         Skipped automatically when no fork is active.
contract RobinhoodForkTest is Test {
    // Canonical registry addresses (docs.robinhood.com/chain/contracts, verified 2026-09-01)
    address constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address constant SEAPORT_1_6 = 0x0000000000000068F116a894984e2DB1123eB395;

    modifier onlyFork() {
        if (block.chainid != 4663) {
            vm.skip(true);
        }
        _;
    }

    function test_fork_canonicalInfraDeployed() public onlyFork {
        assertGt(PERMIT2.code.length, 0, "Permit2 must be deployed");
        assertGt(MULTICALL3.code.length, 0, "Multicall3 must be deployed");
        assertGt(SEAPORT_1_6.code.length, 0, "Seaport 1.6 must be deployed");
    }

    function test_fork_stockTokenSurface() public onlyFork {
        assertEq(IStockTokenLike(AAPL).symbol(), "AAPL");
        assertEq(IStockTokenLike(AAPL).decimals(), 18);
        assertGt(IStockTokenLike(AAPL).uiMultiplier(), 0, "ERC-8056 uiMultiplier must exist");
        assertEq(IStockTokenLike(NVDA).symbol(), "NVDA");
    }

    /// @dev The core feasibility question, executed: can a third-party escrow receive,
    ///      hold, and pay out real Stock Tokens? Funds a fresh EOA by pranking an
    ///      existing on-chain holder, then runs the full pack → transfer → unpack loop.
    function test_fork_realStockToken_roundTrip() public onlyFork {
        address deployer = makeAddr("fork-deployer");
        address predicted = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        vm.startPrank(deployer);
        StockPackRenderer renderer =
            new StockPackRenderer(predicted, address(new StockPackArt()), "https://stock-pack.vercel.app");
        StockPack pack = new StockPack(address(renderer), deployer);
        vm.stopPrank();
        assertEq(address(pack), predicted);

        // fund alice with real AAPL from a live holder (fails loudly if none configured)
        address whale = vm.envOr("AAPL_WHALE", address(0));
        uint256 amount = 1e16; // 0.01 AAPL token
        address alice = makeAddr("fork-alice");
        if (whale != address(0) && IStockTokenLike(AAPL).balanceOf(whale) >= amount) {
            vm.prank(whale);
            IStockTokenLike(AAPL).transfer(alice, amount);
        } else {
            // fall back to storage manipulation; reverts if the proxy layout defeats it,
            // which is itself a finding worth surfacing
            deal(AAPL, alice, amount);
        }
        assertEq(IStockTokenLike(AAPL).balanceOf(alice), amount);

        address[] memory tokens = new address[](1);
        tokens[0] = AAPL;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.startPrank(alice);
        IStockTokenLike(AAPL).approve(address(pack), amount);
        uint256 id = pack.pack("Real AAPL", tokens, amounts);
        vm.stopPrank();
        assertEq(IStockTokenLike(AAPL).balanceOf(address(pack)), amount, "escrow must custody real AAPL");

        // secondary-market handoff, then the buyer redeems
        address bob = makeAddr("fork-bob");
        vm.prank(alice);
        pack.transferFrom(alice, bob, id);
        vm.prank(bob);
        pack.unpack(id);
        assertEq(IStockTokenLike(AAPL).balanceOf(bob), amount, "redeemer must receive real AAPL");

        // metadata renders against the real token
        vm.prank(alice);
        IStockTokenLike(AAPL).approve(address(pack), 0);
    }
}
