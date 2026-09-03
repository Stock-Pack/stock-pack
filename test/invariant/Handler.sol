// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {StockPack} from "../../src/StockPack.sol";
import {MockStockToken} from "../../src/mocks/MockStockToken.sol";
import {BlocklistToken} from "../mocks/WeirdTokens.sol";

/// @notice Bounded-actor handler driving the escrow through pack / transfer / unpack /
///         emergencyUnpack / claim / donate / issuer-freeze actions, with ghost
///         accumulators the invariant suite checks against. Every action guards its
///         own preconditions (fail_on_revert = true).
contract Handler is CommonBase, StdCheats, StdUtils {
    StockPack public pack;
    BlocklistToken public blk;
    address[] public allTokens; // sorted ascending at construction
    address[3] public actors;
    bool public blkFrozen; // blk blocklists the escrow contract itself

    // ghosts
    uint256[] public liveIds;
    mapping(uint256 => uint256) internal liveIndex; // 1-based
    uint256[] public burnedIds;
    mapping(uint256 => address[]) public basketTokensOf;
    mapping(uint256 => uint256[]) public basketAmountsOf;
    mapping(address => uint256) public ghostLive; // token => sum over live baskets
    mapping(address => uint256) public ghostClaims; // token => sum of unclaimed emergency rows
    mapping(address => uint256) public ghostDonated; // token => direct donations

    // non-vacuity counters
    uint256 public packCalls;
    uint256 public transferCalls;
    uint256 public unpackCalls;
    uint256 public emergencyCalls;
    uint256 public claimCalls;
    uint256 public donateCalls;

    constructor(StockPack pack_, address[] memory tokens_, BlocklistToken blk_) {
        pack = pack_;
        blk = blk_;
        allTokens = tokens_;
        // sort ascending so any subset is a valid strictly-ascending basket
        for (uint256 i = 1; i < allTokens.length; ++i) {
            address t = allTokens[i];
            uint256 j = i;
            while (j > 0 && allTokens[j - 1] > t) {
                allTokens[j] = allTokens[j - 1];
                --j;
            }
            allTokens[j] = t;
        }
        actors[0] = makeAddr("actor0");
        actors[1] = makeAddr("actor1");
        actors[2] = makeAddr("actor2");
        for (uint256 a; a < 3; ++a) {
            for (uint256 t; t < allTokens.length; ++t) {
                vm.prank(actors[a]);
                (bool ok,) = allTokens[t].call(
                    abi.encodeWithSignature("approve(address,uint256)", address(pack), type(uint256).max)
                );
                require(ok, "approve failed");
            }
        }
    }

    // ─── actions ─────────────────────────────────────────────────────────────

    function packBasket(uint256 actorSeed, uint256 mask, uint256[4] calldata amountSeeds) external {
        address actor = actors[bound(actorSeed, 0, 2)];
        mask = bound(mask, 1, (1 << allTokens.length) - 1);

        uint256 n;
        address[] memory tokens = new address[](allTokens.length);
        uint256[] memory amounts = new uint256[](allTokens.length);
        for (uint256 i; i < allTokens.length; ++i) {
            if (mask & (1 << i) == 0) continue;
            if (blkFrozen && allTokens[i] == address(blk)) continue; // frozen token can't be deposited
            tokens[n] = allTokens[i];
            amounts[n] = bound(amountSeeds[i % 4], 1, 900e18); // MockStockToken.MAX_MINT cap
            ++n;
        }
        if (n == 0) return;
        assembly {
            mstore(tokens, n)
            mstore(amounts, n)
        }

        for (uint256 i; i < n; ++i) {
            (bool ok,) = tokens[i].call(abi.encodeWithSignature("mint(address,uint256)", actor, amounts[i]));
            require(ok, "mint failed");
        }
        vm.prank(actor);
        uint256 id = pack.pack("Invariant Basket", tokens, amounts);

        liveIds.push(id);
        liveIndex[id] = liveIds.length;
        basketTokensOf[id] = tokens;
        basketAmountsOf[id] = amounts;
        for (uint256 i; i < n; ++i) {
            ghostLive[tokens[i]] += amounts[i];
        }
        ++packCalls;
    }

    function transferNFT(uint256 idSeed, uint256 toSeed) external {
        if (liveIds.length == 0) return;
        uint256 id = liveIds[bound(idSeed, 0, liveIds.length - 1)];
        address owner = pack.ownerOf(id);
        address to = actors[bound(toSeed, 0, 2)];
        if (to == owner) return;
        vm.prank(owner);
        pack.transferFrom(owner, to, id);
        ++transferCalls;
    }

    function unpackBasket(uint256 idSeed) external {
        if (liveIds.length == 0) return;
        uint256 id = liveIds[bound(idSeed, 0, liveIds.length - 1)];
        if (blkFrozen && _basketContains(id, address(blk))) return; // would revert
        address owner = pack.ownerOf(id);

        address[] memory tokens = basketTokensOf[id];
        uint256[] memory amounts = basketAmountsOf[id];
        vm.prank(owner);
        pack.unpack(id);

        for (uint256 i; i < tokens.length; ++i) {
            ghostLive[tokens[i]] -= amounts[i];
        }
        _removeLive(id);
        ++unpackCalls;
    }

    function emergencyUnpackBasket(uint256 idSeed) external {
        if (liveIds.length == 0) return;
        uint256 id = liveIds[bound(idSeed, 0, liveIds.length - 1)];
        address owner = pack.ownerOf(id);

        address[] memory tokens = basketTokensOf[id];
        uint256[] memory amounts = basketAmountsOf[id];
        vm.prank(owner);
        pack.emergencyUnpack(id);

        for (uint256 i; i < tokens.length; ++i) {
            ghostLive[tokens[i]] -= amounts[i];
            ghostClaims[tokens[i]] += amounts[i];
        }
        _removeLive(id);
        ++emergencyCalls;
    }

    function claimToken(uint256 actorSeed, uint256 tokenSeed) external {
        address actor = actors[bound(actorSeed, 0, 2)];
        address token = allTokens[bound(tokenSeed, 0, allTokens.length - 1)];
        uint256 owed = pack.claimable(actor, token);
        if (owed == 0) return;
        if (blkFrozen && token == address(blk)) return; // transfer would revert
        (, bytes memory ret) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(pack)));
        if (abi.decode(ret, (uint256)) == 0) return;

        vm.prank(actor);
        pack.claim(token, actor);
        // no shortfall is possible in this handler (no rebasing) → full payout
        ghostClaims[token] -= owed;
        ++claimCalls;
    }

    function donate(uint256 tokenSeed, uint256 amountSeed) external {
        address token = allTokens[bound(tokenSeed, 0, allTokens.length - 1)];
        uint256 amount = bound(amountSeed, 1, 900e18);
        (bool ok,) = token.call(abi.encodeWithSignature("mint(address,uint256)", address(pack), amount));
        require(ok, "mint failed");
        ghostDonated[token] += amount;
        ++donateCalls;
    }

    function toggleFreeze() external {
        blkFrozen = !blkFrozen;
        blk.setBlocked(address(pack), blkFrozen);
    }

    // ─── views for the invariant suite ───────────────────────────────────────

    function tokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    function liveCount() external view returns (uint256) {
        return liveIds.length;
    }

    function burnedCount() external view returns (uint256) {
        return burnedIds.length;
    }

    function basketOf(uint256 id) external view returns (address[] memory, uint256[] memory) {
        return (basketTokensOf[id], basketAmountsOf[id]);
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    // ─── internal ────────────────────────────────────────────────────────────

    function _basketContains(uint256 id, address token) internal view returns (bool) {
        address[] memory tokens = basketTokensOf[id];
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i] == token) return true;
        }
        return false;
    }

    function _removeLive(uint256 id) internal {
        uint256 idx = liveIndex[id];
        uint256 last = liveIds[liveIds.length - 1];
        liveIds[idx - 1] = last;
        liveIndex[last] = idx;
        liveIds.pop();
        delete liveIndex[id];
        burnedIds.push(id);
    }
}
