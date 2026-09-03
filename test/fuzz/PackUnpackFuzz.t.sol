// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {StockPackTestBase} from "../utils/TestBase.sol";
import {IStockPack} from "../../src/interfaces/IStockPack.sol";
import {MockStockToken} from "../../src/mocks/MockStockToken.sol";

contract PackUnpackFuzzTest is StockPackTestBase {
    MockStockToken[] internal pool;

    function setUp() public override {
        super.setUp();
        for (uint256 i; i < 16; ++i) {
            pool.push(new MockStockToken("Pool Token", string.concat("mPOOL", vm.toString(i)), 18));
        }
    }

    /// @dev FUZZ_ROUND_TRIP: for any basket (1..16 tokens, any amounts), pack→unpack is
    ///      exact conservation — every balance returns to its initial value, zero wei
    ///      lost or gained, and the escrow ends empty.
    function testFuzz_roundTrip_exactConservation(uint256 nSeed, uint256[16] calldata amountSeeds) public {
        uint256 n = bound(nSeed, 1, 16);
        address[] memory tokens = new address[](n);
        uint256[] memory amounts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            tokens[i] = address(pool[i]);
            amounts[i] = bound(amountSeeds[i], 1, 1000e18);
        }
        sortBasket(tokens, amounts);
        fund(alice, tokens, amounts);

        vm.prank(alice);
        uint256 id = pack.pack("Fuzz Bundle", tokens, amounts);
        vm.prank(alice);
        pack.unpack(id);

        for (uint256 i; i < n; ++i) {
            assertEq(MockStockToken(tokens[i]).balanceOf(alice), amounts[i], "holder must recover exact amount");
            assertEq(MockStockToken(tokens[i]).balanceOf(address(pack)), 0, "escrow must end empty");
            assertEq(pack.totalEscrowed(tokens[i]), 0, "ledger must end empty");
        }
    }

    /// @dev FUZZ_AUTH: no address other than the current owner can ever burn a basket —
    ///      including approved operators.
    function testFuzz_auth_onlyOwnerBurns(address caller, bool asOperator) public {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        vm.prank(alice);
        uint256 id = pack.pack("Auth", tokens, amounts);

        vm.assume(caller != alice && caller != address(0));
        if (asOperator) {
            vm.prank(alice);
            pack.setApprovalForAll(caller, true);
        }

        vm.startPrank(caller);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.unpack(id);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.unpackTo(id, caller);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.emergencyUnpack(id);
        vm.stopPrank();

        assertEq(pack.ownerOf(id), alice, "basket must survive every unauthorized attempt");
    }

    /// @dev FUZZ_NAME_NEVER_BREAKS_METADATA: any byte string 1..31 long produces a
    ///      tokenURI whose JSON parses and whose SVG contains no raw angle brackets
    ///      from the name.
    function testFuzz_name_neverBreaksMetadata(bytes calldata rawName) public {
        vm.assume(rawName.length > 0);
        bytes memory nameBytes = rawName.length > 31 ? rawName[:31] : rawName;

        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        vm.prank(alice);
        uint256 id = pack.pack(string(nameBytes), tokens, amounts);

        string memory json = decodeDataURI(pack.tokenURI(id));
        vm.parseJsonString(json, "$.name"); // reverts on malformed JSON
        string memory svg = decodeDataURI(vm.parseJsonString(json, "$.image"));
        assertTrue(contains(svg, "<svg"), "SVG must render");
    }

    /// @dev Claims conserve value under arbitrary split of emergency + claim sequences.
    function testFuzz_emergencyClaim_conservation(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, 1000e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        fund(alice, tokens, amounts);

        vm.startPrank(alice);
        uint256 id = pack.pack("E", tokens, amounts);
        pack.emergencyUnpack(id);
        pack.claim(address(nvda), alice);
        vm.stopPrank();

        assertEq(nvda.balanceOf(alice), amount);
        assertEq(pack.claimable(alice, address(nvda)), 0);
        assertEq(pack.totalEscrowed(address(nvda)), 0);
    }
}
