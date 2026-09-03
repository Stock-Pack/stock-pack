// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Test} from "forge-std/Test.sol";

import {StockPack} from "../../src/StockPack.sol";
import {StockPackArt} from "../../src/art/StockPackArt.sol";
import {StockPackRenderer} from "../../src/StockPackRenderer.sol";
import {MockStockToken} from "../../src/mocks/MockStockToken.sol";
import {BlocklistToken} from "../mocks/WeirdTokens.sol";
import {IStockPack} from "../../src/interfaces/IStockPack.sol";
import {Handler} from "./Handler.sol";

interface IERC20Bal {
    function balanceOf(address) external view returns (uint256);
}

contract StockPackInvariants is Test {
    StockPack internal pack;
    Handler internal handler;
    address[] internal toks;

    function setUp() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        StockPackRenderer renderer =
            new StockPackRenderer(predicted, address(new StockPackArt()), "https://stock-pack.vercel.app");
        pack = new StockPack(address(renderer), makeAddr("artist"));

        BlocklistToken blk = new BlocklistToken();
        toks.push(address(new MockStockToken("Mock NVIDIA", "mNVDA", 18)));
        toks.push(address(new MockStockToken("Mock Apple", "mAAPL", 18)));
        toks.push(address(new MockStockToken("Mock Tesla", "mTSLA", 6)));
        toks.push(address(blk));

        handler = new Handler(pack, toks, blk);
        targetContract(address(handler));
    }

    /// INV_SOLVENCY — the pool always covers the ledger; with donations tracked, exactly.
    function invariant_solvency() public view {
        for (uint256 i; i < toks.length; ++i) {
            uint256 bal = IERC20Bal(toks[i]).balanceOf(address(pack));
            uint256 owed = pack.totalEscrowed(toks[i]);
            assertGe(bal, owed, "INV_SOLVENCY: pool must cover the ledger");
            assertEq(bal, owed + handler.ghostDonated(toks[i]), "INV_SOLVENCY: pool == ledger + donations");
        }
    }

    /// INV_LEDGER — totalEscrowed == live basket contents + unclaimed emergency rows.
    function invariant_ledger() public view {
        for (uint256 i; i < toks.length; ++i) {
            assertEq(
                pack.totalEscrowed(toks[i]),
                handler.ghostLive(toks[i]) + handler.ghostClaims(toks[i]),
                "INV_LEDGER: accounting identity broken"
            );
        }
    }

    /// INV_SUPPLY + INV_MONOTONIC_IDS — every minted id is exactly live or burned, once.
    function invariant_supply_and_monotonic_ids() public view {
        assertEq(pack.totalMinted(), handler.liveCount() + handler.burnedCount(), "INV_SUPPLY: minted == live + burned");
        for (uint256 i; i < handler.liveCount(); ++i) {
            pack.ownerOf(handler.liveIds(i)); // must not revert
        }
    }

    /// INV_NO_RESIDUAL — burned ids have zero rows, zero meta; reads revert.
    function invariant_no_residual_state() public {
        uint256 n = handler.burnedCount();
        for (uint256 i; i < n; ++i) {
            uint256 id = handler.burnedIds(i);
            vm.expectRevert(IStockPack.NonexistentToken.selector);
            pack.getBasket(id);
            vm.expectRevert(IStockPack.NonexistentToken.selector);
            pack.bundleMeta(id);
        }
    }

    /// INV_REDEMPTION_FLOOR — the product promise, executed: after any run, every live
    /// basket unpacks for exactly its recorded amounts, every claim drains in full, and
    /// the pool ends holding only donations.
    function afterInvariant() public {
        // lift any issuer freeze so the sweep can settle everything
        if (handler.blkFrozen()) handler.toggleFreeze();

        // NOTE: unpacking goes straight to the escrow, bypassing the handler's ghosts —
        // iterate the (now-static) live list by index instead of polling liveCount.
        uint256 liveN = handler.liveCount();
        for (uint256 k; k < liveN; ++k) {
            uint256 id = handler.liveIds(k);
            address owner = pack.ownerOf(id);
            (address[] memory tokens, uint256[] memory amounts) = handler.basketOf(id);
            uint256[] memory before = new uint256[](tokens.length);
            for (uint256 i; i < tokens.length; ++i) {
                before[i] = IERC20Bal(tokens[i]).balanceOf(owner);
            }
            vm.prank(owner);
            pack.unpack(id);
            for (uint256 i; i < tokens.length; ++i) {
                assertEq(
                    IERC20Bal(tokens[i]).balanceOf(owner) - before[i],
                    amounts[i],
                    "INV_REDEMPTION_FLOOR: redeemer must receive exactly the recorded amount"
                );
            }
        }

        for (uint256 a; a < 3; ++a) {
            address actor = handler.actorAt(a);
            for (uint256 t; t < toks.length; ++t) {
                uint256 owed = pack.claimable(actor, toks[t]);
                if (owed == 0) continue;
                uint256 before = IERC20Bal(toks[t]).balanceOf(actor);
                vm.prank(actor);
                pack.claim(toks[t], actor);
                assertEq(IERC20Bal(toks[t]).balanceOf(actor) - before, owed, "claims must drain in full");
            }
        }

        for (uint256 t; t < toks.length; ++t) {
            assertEq(pack.totalEscrowed(toks[t]), 0, "ledger must reach zero after full settlement");
            assertEq(
                IERC20Bal(toks[t]).balanceOf(address(pack)),
                handler.ghostDonated(toks[t]),
                "pool must end holding exactly the donations"
            );
        }
    }
}
