// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {StockPackTestBase} from "../utils/TestBase.sol";
import {IStockPack} from "../../src/interfaces/IStockPack.sol";
import {RebasingToken, PausableToken, ReentrantToken, RevertOnZeroToken} from "../mocks/WeirdTokens.sol";

/// @notice Defines EXACT behavior under each adversarial-token scenario — most
///         importantly the downward-rebase contagion across a commingled pool, where
///         the recovery path must be best-effort partial claims, never a permanent brick.
contract WeirdTokensTest is StockPackTestBase {
    // ─────────────────────────────────────────────────────────────────────────
    // Rebasing contagion: two baskets share REB, a reverse split hits the pool
    // ─────────────────────────────────────────────────────────────────────────

    function test_rebasing_downward_contagion_definedBehavior() public {
        RebasingToken reb = new RebasingToken();

        // Alice and Bob each escrow 10 REB in separate baskets (factor = 1.0)
        address[] memory tokens = new address[](1);
        tokens[0] = address(reb);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;

        reb.mint(alice, 10e18);
        vm.startPrank(alice);
        reb.approve(address(pack), type(uint256).max);
        uint256 idA = pack.pack("A", tokens, amounts);
        vm.stopPrank();

        reb.mint(bob, 10e18);
        vm.startPrank(bob);
        reb.approve(address(pack), type(uint256).max);
        uint256 idB = pack.pack("B", tokens, amounts);
        vm.stopPrank();

        assertEq(reb.balanceOf(address(pack)), 20e18);
        assertEq(pack.totalEscrowed(address(reb)), 20e18);

        // Reverse split: every balance halves. The pool now holds 10, owes 20.
        reb.setFactor(5e17);
        assertEq(reb.balanceOf(address(pack)), 10e18);

        // (1) First redeemer drains the pool at full recorded amount — FCFS by design.
        vm.prank(alice);
        pack.unpack(idA);
        assertEq(reb.balanceOf(alice), 10e18);
        assertEq(reb.balanceOf(address(pack)), 0);

        // (2) Second atomic unpack reverts: pool is short.
        vm.prank(bob);
        vm.expectRevert();
        pack.unpack(idB);

        // (3) emergencyUnpack always works (zero external calls)...
        vm.prank(bob);
        pack.emergencyUnpack(idB);
        assertEq(pack.claimable(bob, address(reb)), 10e18);

        // (4) ...and claim() is BEST-EFFORT: pays min(owed, pool), never bricks.
        //     Pool is 0 → NothingToClaim now, claim survives for later.
        vm.prank(bob);
        vm.expectRevert(IStockPack.NothingToClaim.selector);
        pack.claim(address(reb), bob);
        assertEq(pack.claimable(bob, address(reb)), 10e18);

        // Upward drift (or a donation) refills the pool → partial claim pays out
        // whatever is transferable and leaves the shortfall claimable.
        reb.mint(address(pack), 4e18); // simulate partial recovery
        vm.prank(bob);
        pack.claim(address(reb), bob);
        assertEq(reb.balanceOf(bob), 4e18);
        assertEq(pack.claimable(bob, address(reb)), 6e18, "shortfall must remain claimable");
        assertEq(pack.totalEscrowed(address(reb)), 6e18, "ledger tracks only what is still owed");

        reb.mint(address(pack), 6e18);
        vm.prank(bob);
        pack.claim(address(reb), bob);
        assertEq(reb.balanceOf(bob), 10e18);
        assertEq(pack.claimable(bob, address(reb)), 0);
        assertEq(pack.totalEscrowed(address(reb)), 0);
    }

    function test_rebasing_upward_neverSkewsRedemptions() public {
        RebasingToken reb = new RebasingToken();
        address[] memory tokens = new address[](1);
        tokens[0] = address(reb);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e18;
        reb.mint(alice, 10e18);
        vm.startPrank(alice);
        reb.approve(address(pack), type(uint256).max);
        uint256 id = pack.pack("Up", tokens, amounts);
        vm.stopPrank();

        reb.setFactor(2e18); // balances double; ledger reads storage, not balanceOf
        assertEq(pack.totalEscrowed(address(reb)), 10e18);

        vm.prank(alice);
        pack.unpack(id);
        // redeemer receives exactly the recorded amount; surplus stays in the pool
        assertEq(reb.balanceOf(alice), 10e18);
        assertEq(reb.balanceOf(address(pack)), 10e18);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pause (the Robinhood beacon-proxy scenario)
    // ─────────────────────────────────────────────────────────────────────────

    function test_paused_oneTokenNeverBricksTheOthers() public {
        PausableToken pau = new PausableToken();
        address[] memory tokens = new address[](2);
        tokens[0] = address(pau);
        tokens[1] = address(nvda);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2e18;
        amounts[1] = 1e18;
        sortBasket(tokens, amounts);
        pau.mint(alice, 2e18);
        nvda.mint(alice, 1e18);
        vm.startPrank(alice);
        pau.approve(address(pack), type(uint256).max);
        nvda.approve(address(pack), type(uint256).max);
        uint256 id = pack.pack("Halted", tokens, amounts);
        vm.stopPrank();

        pau.setPaused(true);
        vm.prank(alice);
        vm.expectRevert("PAU: paused");
        pack.unpack(id);

        vm.startPrank(alice);
        pack.emergencyUnpack(id);
        pack.claim(address(nvda), alice); // healthy constituent exits immediately
        vm.stopPrank();
        assertEq(nvda.balanceOf(alice), 1e18);

        pau.setPaused(false);
        vm.prank(alice);
        pack.claim(address(pau), alice);
        assertEq(pau.balanceOf(alice), 2e18);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reentrancy through token hooks
    // ─────────────────────────────────────────────────────────────────────────

    function test_reentrantToken_cannotReenter_pack_orUnpack() public {
        ReentrantToken ree = new ReentrantToken();
        address[] memory tokens = new address[](1);
        tokens[0] = address(ree);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        ree.mint(alice, 2e18);
        vm.prank(alice);
        ree.approve(address(pack), type(uint256).max);

        // hook fires during pack()'s safeTransferFrom and tries to re-enter pack()
        ree.arm(address(pack), abi.encodeCall(IStockPack.pack, ("evil", tokens, amounts)));
        vm.prank(alice);
        uint256 id = pack.pack("Legit", tokens, amounts);
        assertFalse(ree.lastReentrySucceeded(), "reentry into pack must be blocked");
        assertEq(pack.totalMinted(), 1, "no second basket may appear");

        // hook fires during unpack()'s safeTransfer and tries to unpack again
        ree.arm(address(pack), abi.encodeCall(IStockPack.unpack, (id)));
        vm.prank(alice);
        pack.unpack(id);
        assertFalse(ree.lastReentrySucceeded(), "reentry into unpack must be blocked");
        assertEq(ree.balanceOf(alice), 2e18, "exact conservation despite hostile hook");
        assertEq(pack.totalEscrowed(address(ree)), 0);
    }

    function test_reentrantToken_cannotDoubleClaim() public {
        ReentrantToken ree = new ReentrantToken();
        address[] memory tokens = new address[](1);
        tokens[0] = address(ree);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        ree.mint(alice, 1e18);
        vm.prank(alice);
        ree.approve(address(pack), type(uint256).max);
        vm.prank(alice);
        uint256 id = pack.pack("x", tokens, amounts);
        vm.prank(alice);
        pack.emergencyUnpack(id);

        ree.arm(address(pack), abi.encodeCall(IStockPack.claim, (address(ree), alice)));
        vm.prank(alice);
        pack.claim(address(ree), alice);
        assertFalse(ree.lastReentrySucceeded(), "reentry into claim must be blocked");
        assertEq(ree.balanceOf(alice), 1e18, "claim pays exactly once");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Zero-revert token: escrow never transfers 0, so it composes fine
    // ─────────────────────────────────────────────────────────────────────────

    function test_revertOnZeroToken_roundTrips() public {
        RevertOnZeroToken roz = new RevertOnZeroToken();
        address[] memory tokens = new address[](1);
        tokens[0] = address(roz);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 7e18;
        roz.mint(alice, 7e18);
        vm.startPrank(alice);
        roz.approve(address(pack), type(uint256).max);
        uint256 id = pack.pack("x", tokens, amounts);
        pack.unpack(id);
        vm.stopPrank();
        assertEq(roz.balanceOf(alice), 7e18);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Donations: accounting never reads live balanceOf
    // ─────────────────────────────────────────────────────────────────────────

    function test_directDonation_neverSkewsLedgerOrRedemption() public {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        vm.prank(alice);
        uint256 id = pack.pack("x", tokens, amounts);

        nvda.mint(address(pack), 100e18); // unsolicited donation
        assertEq(pack.totalEscrowed(address(nvda)), pack.totalEscrowed(address(nvda)));

        vm.prank(alice);
        pack.unpack(id);
        for (uint256 i; i < tokens.length; ++i) {
            assertEq(pack.totalEscrowed(tokens[i]), 0);
        }
        // redeemer got exactly the recorded amounts; the donation stays stranded
        assertEq(nvda.balanceOf(address(pack)), 100e18);
    }
}
