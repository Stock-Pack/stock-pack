// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {StockPackTestBase} from "../utils/TestBase.sol";
import {IStockPack} from "../../src/interfaces/IStockPack.sol";
import {ISignatureTransfer} from "../../src/interfaces/external/ISignatureTransfer.sol";
import {StockPackRenderer} from "../../src/StockPackRenderer.sol";
import {MockStockToken} from "../../src/mocks/MockStockToken.sol";
import {FeeOnTransferToken, BlocklistToken, NoReturnToken, NaivePacker} from "../mocks/WeirdTokens.sol";

contract StockPackTest is StockPackTestBase {
    address internal constant PERMIT2_ADDR = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 internal constant PERMIT_BATCH_TYPEHASH = keccak256(
        "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    // ─────────────────────────────────────────────────────────────────────────
    // pack — happy path
    // ─────────────────────────────────────────────────────────────────────────

    function test_pack_happyPath() public {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();

        vm.expectEmit(true, true, false, true);
        emit IStockPack.Packed(1, alice, "The Big Tech Bundle", tokens, amounts);
        vm.prank(alice);
        uint256 id = pack.pack("The Big Tech Bundle", tokens, amounts);

        assertEq(id, 1);
        assertEq(pack.ownerOf(1), alice);
        assertEq(pack.totalMinted(), 1);
        assertEq(pack.balanceOf(alice), 1);

        (address[] memory t, uint256[] memory a) = pack.getBasket(1);
        for (uint256 i; i < 3; ++i) {
            assertEq(t[i], tokens[i]);
            assertEq(a[i], amounts[i]);
            assertEq(pack.totalEscrowed(tokens[i]), amounts[i]);
            assertEq(MockStockToken(tokens[i]).balanceOf(address(pack)), amounts[i]);
            assertEq(MockStockToken(tokens[i]).balanceOf(alice), 0);
        }

        (string memory name, address creator, uint64 sealedAt) = pack.bundleMeta(1);
        assertEq(name, "The Big Tech Bundle");
        assertEq(creator, alice);
        assertEq(sealedAt, uint64(block.timestamp));
    }

    function test_pack_singleToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1; // 1 wei basket is legal by design
        fund(alice, tokens, amounts);
        vm.prank(alice);
        assertEq(pack.pack("Dust", tokens, amounts), 1);
    }

    function test_pack_monotonicIds_neverReused() public {
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        vm.prank(alice);
        pack.pack("One", tokens, amounts);
        vm.prank(alice);
        pack.unpack(1);

        fund(alice, tokens, amounts);
        vm.prank(alice);
        uint256 second = pack.pack("Two", tokens, amounts);
        assertEq(second, 2, "burned id must never be reused");
        assertEq(pack.totalMinted(), 2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // pack — full revert matrix
    // ─────────────────────────────────────────────────────────────────────────

    function test_pack_revert_lengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(nvda);
        tokens[1] = address(aapl);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        vm.expectRevert(IStockPack.LengthMismatch.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_emptyBasket() public {
        vm.expectRevert(IStockPack.EmptyBasket.selector);
        pack.pack("x", new address[](0), new uint256[](0));
    }

    function test_pack_revert_basketTooLarge() public {
        uint256 n = 17;
        address[] memory tokens = new address[](n);
        uint256[] memory amounts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            tokens[i] = address(uint160(i + 1));
            amounts[i] = 1;
        }
        vm.expectRevert(IStockPack.BasketTooLarge.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_duplicateToken() public {
        // fund the first (valid) entry so the check actually reaches entry #2
        nvda.mint(address(this), 2e18);
        nvda.approve(address(pack), type(uint256).max);
        address[] memory tokens = new address[](2);
        tokens[0] = address(nvda);
        tokens[1] = address(nvda);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;
        vm.expectRevert(IStockPack.TokensNotSortedUnique.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_descendingTokens() public {
        nvda.mint(address(this), 1e18);
        nvda.approve(address(pack), type(uint256).max);
        aapl.mint(address(this), 1e18);
        aapl.approve(address(pack), type(uint256).max);
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;
        (tokens[0], tokens[1]) =
            address(nvda) > address(aapl) ? (address(nvda), address(aapl)) : (address(aapl), address(nvda));
        vm.expectRevert(IStockPack.TokensNotSortedUnique.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_zeroAddressToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        vm.expectRevert(IStockPack.TokensNotSortedUnique.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_zeroAmount() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(IStockPack.ZeroAmount.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_selfToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(pack);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        vm.expectRevert(IStockPack.SelfToken.selector);
        pack.pack("x", tokens, amounts);
    }

    function test_pack_revert_nameLength() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        fund(alice, tokens, amounts);

        vm.prank(alice);
        vm.expectRevert(IStockPack.NameLength.selector);
        pack.pack("", tokens, amounts);

        vm.prank(alice);
        vm.expectRevert(IStockPack.NameLength.selector);
        pack.pack("abcdefghijklmnopqrstuvwxyzabcdef", tokens, amounts); // 32 bytes

        vm.prank(alice);
        assertEq(pack.pack("abcdefghijklmnopqrstuvwxyzabcde", tokens, amounts), 1); // 31 bytes OK
    }

    function test_pack_revert_feeOnTransfer_lowAndHighFee() public {
        uint256[] memory fees = new uint256[](2);
        fees[0] = 1; // 1 bps
        fees[1] = 5000; // 50%
        for (uint256 i; i < fees.length; ++i) {
            FeeOnTransferToken fee = new FeeOnTransferToken(fees[i]);
            fee.mint(alice, 10e18);
            vm.prank(alice);
            fee.approve(address(pack), type(uint256).max);

            address[] memory tokens = new address[](1);
            tokens[0] = address(fee);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1e18;

            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(IStockPack.FeeOnTransferRejected.selector, address(fee)));
            pack.pack("x", tokens, amounts);
        }
    }

    function test_pack_noReturnToken_accepted() public {
        NoReturnToken nrt = new NoReturnToken();
        nrt.mint(alice, 5e18);
        vm.prank(alice);
        nrt.approve(address(pack), type(uint256).max);

        address[] memory tokens = new address[](1);
        tokens[0] = address(nrt);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5e18;

        vm.prank(alice);
        uint256 id = pack.pack("USDT-style", tokens, amounts);
        vm.prank(alice);
        pack.unpack(id);
        assertEq(nrt.balanceOf(alice), 5e18);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // unpack — auth and happy paths
    // ─────────────────────────────────────────────────────────────────────────

    function _packedBigTech() internal returns (uint256 id, address[] memory tokens, uint256[] memory amounts) {
        (tokens, amounts) = bigTechBasket();
        vm.prank(alice);
        id = pack.pack("The Big Tech Bundle", tokens, amounts);
    }

    function test_unpack_buyerRedeemsAfterTransfer() public {
        (uint256 id, address[] memory tokens, uint256[] memory amounts) = _packedBigTech();

        vm.prank(alice);
        pack.transferFrom(alice, bob, id);

        vm.expectEmit(true, true, true, true);
        emit IStockPack.Unpacked(id, bob, bob);
        vm.prank(bob);
        pack.unpack(id);

        for (uint256 i; i < tokens.length; ++i) {
            assertEq(MockStockToken(tokens[i]).balanceOf(bob), amounts[i]);
            assertEq(pack.totalEscrowed(tokens[i]), 0);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
        pack.ownerOf(id);
        vm.expectRevert(IStockPack.NonexistentToken.selector);
        pack.getBasket(id);
        vm.expectRevert(IStockPack.NonexistentToken.selector);
        pack.bundleMeta(id);
    }

    function test_unpackTo_blocklistedHolderRedeemsToCleanAddress() public {
        BlocklistToken blk = new BlocklistToken();
        blk.mint(alice, 3e18);
        vm.prank(alice);
        blk.approve(address(pack), type(uint256).max);
        address[] memory tokens = new address[](1);
        tokens[0] = address(blk);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3e18;
        vm.prank(alice);
        uint256 id = pack.pack("x", tokens, amounts);

        blk.setBlocked(alice, true); // issuer freezes the holder, not the escrow
        vm.prank(alice);
        pack.unpackTo(id, bob);
        assertEq(blk.balanceOf(bob), 3e18);
    }

    function test_unpack_revert_strangerAndApprovedOperator() public {
        (uint256 id,,) = _packedBigTech();

        // stranger
        vm.prank(bob);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.unpack(id);

        // per-token approval must NOT grant redemption
        vm.prank(alice);
        pack.approve(bob, id);
        vm.prank(bob);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.unpack(id);

        // operator approval must NOT grant redemption (NFT Trader lesson)
        vm.prank(alice);
        pack.setApprovalForAll(bob, true);
        vm.prank(bob);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.unpack(id);
        vm.prank(bob);
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.emergencyUnpack(id);

        // ...but the operator can still transfer, and the new owner can redeem
        vm.prank(bob);
        pack.transferFrom(alice, bob, id);
        vm.prank(bob);
        pack.unpack(id);
    }

    function test_unpackTo_revert_zeroRecipient() public {
        (uint256 id,,) = _packedBigTech();
        vm.prank(alice);
        vm.expectRevert(IStockPack.ZeroRecipient.selector);
        pack.unpackTo(id, address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // emergencyUnpack + claim matrix
    // ─────────────────────────────────────────────────────────────────────────

    function _packedWithBlocklist()
        internal
        returns (uint256 id, BlocklistToken blk, address[] memory tokens, uint256[] memory amounts)
    {
        blk = new BlocklistToken();
        tokens = new address[](2);
        tokens[0] = address(blk);
        tokens[1] = address(nvda);
        amounts = new uint256[](2);
        amounts[0] = 4e18;
        amounts[1] = 1e18;
        sortBasket(tokens, amounts);
        blk.mint(alice, 4e18);
        nvda.mint(alice, 1e18);
        vm.startPrank(alice);
        blk.approve(address(pack), type(uint256).max);
        nvda.approve(address(pack), type(uint256).max);
        id = pack.pack("Frozen Mix", tokens, amounts);
        vm.stopPrank();
    }

    function test_emergency_frozenConstituent_fullRecovery() public {
        (uint256 id, BlocklistToken blk,,) = _packedWithBlocklist();

        blk.setBlocked(address(pack), true); // issuer freezes the escrow itself

        // atomic unpack now reverts on the frozen token
        vm.prank(alice);
        vm.expectRevert("BLK: blocked");
        pack.unpack(id);

        // emergencyUnpack cannot be blocked: zero external calls
        vm.prank(alice);
        pack.emergencyUnpack(id);
        assertEq(pack.claimable(alice, address(blk)), 4e18);
        assertEq(pack.claimable(alice, address(nvda)), 1e18);
        // ledger holds until claims are paid
        assertEq(pack.totalEscrowed(address(blk)), 4e18);
        assertEq(pack.totalEscrowed(address(nvda)), 1e18);

        // the healthy token claims immediately; the frozen one waits
        vm.prank(alice);
        pack.claim(address(nvda), alice);
        assertEq(nvda.balanceOf(alice), 1e18);
        assertEq(pack.totalEscrowed(address(nvda)), 0);

        vm.prank(alice);
        vm.expectRevert("BLK: blocked");
        pack.claim(address(blk), alice);
        assertEq(pack.claimable(alice, address(blk)), 4e18, "claim must survive a failed attempt");

        // issuer unfreezes — claim drains
        blk.setBlocked(address(pack), false);
        vm.prank(alice);
        pack.claim(address(blk), alice);
        assertEq(blk.balanceOf(alice), 4e18);
        assertEq(pack.claimable(alice, address(blk)), 0);
        assertEq(pack.totalEscrowed(address(blk)), 0);
    }

    function test_emergency_claimsAreAdditiveAcrossBaskets() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        fund(alice, tokens, amounts);
        vm.prank(alice);
        uint256 a = pack.pack("A", tokens, amounts);
        fund(alice, tokens, amounts);
        vm.prank(alice);
        uint256 b = pack.pack("B", tokens, amounts);

        vm.startPrank(alice);
        pack.emergencyUnpack(a);
        pack.emergencyUnpack(b);
        vm.stopPrank();
        assertEq(pack.claimable(alice, address(nvda)), 2e18);

        vm.prank(alice);
        pack.claim(address(nvda), alice);
        assertEq(nvda.balanceOf(alice), 2e18);
    }

    function test_claim_revert_nothingToClaim_andZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(IStockPack.NothingToClaim.selector);
        pack.claim(address(nvda), alice);

        vm.prank(alice);
        vm.expectRevert(IStockPack.ZeroRecipient.selector);
        pack.claim(address(nvda), address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // packWithPermit2 — one signature funds the whole basket
    // ─────────────────────────────────────────────────────────────────────────

    function _etchPermit2() internal {
        vm.etch(PERMIT2_ADDR, vm.parseBytes(vm.readFile("test/fixtures/permit2.bytecode.txt")));
    }

    function _signPermit(ISignatureTransfer.PermitBatchTransferFrom memory permit, address spender, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        bytes32[] memory permHashes = new bytes32[](permit.permitted.length);
        for (uint256 i; i < permit.permitted.length; ++i) {
            permHashes[i] = keccak256(
                abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i].token, permit.permitted[i].amount)
            );
        }
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_BATCH_TYPEHASH, keccak256(abi.encodePacked(permHashes)), spender, permit.nonce, permit.deadline
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", ISignatureTransfer(PERMIT2_ADDR).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_packWithPermit2_happyPath() public {
        _etchPermit2();
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        // alice approves Permit2 once per token (the standing pattern real wallets use)
        for (uint256 i; i < tokens.length; ++i) {
            vm.prank(alice);
            MockStockToken(tokens[i]).approve(PERMIT2_ADDR, type(uint256).max);
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit;
        permit.permitted = new ISignatureTransfer.TokenPermissions[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            permit.permitted[i] = ISignatureTransfer.TokenPermissions({token: tokens[i], amount: amounts[i]});
        }
        permit.nonce = 7;
        permit.deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit(permit, address(pack), aliceKey);
        vm.prank(alice);
        uint256 id = pack.packWithPermit2("Permit2 Bundle", permit, sig);

        assertEq(pack.ownerOf(id), alice);
        (address[] memory t, uint256[] memory a) = pack.getBasket(id);
        for (uint256 i; i < tokens.length; ++i) {
            // basket derives solely from permit.permitted — declaration == funding
            assertEq(t[i], tokens[i]);
            assertEq(a[i], amounts[i]);
            assertEq(pack.totalEscrowed(tokens[i]), amounts[i]);
        }
    }

    function test_packWithPermit2_revert_unsortedPermitted() public {
        _etchPermit2();
        (address[] memory tokens, uint256[] memory amounts) = bigTechBasket();
        ISignatureTransfer.PermitBatchTransferFrom memory permit;
        permit.permitted = new ISignatureTransfer.TokenPermissions[](2);
        // deliberately descending
        (address hi, address lo) = tokens[0] > tokens[1] ? (tokens[0], tokens[1]) : (tokens[1], tokens[0]);
        permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: hi, amount: amounts[0]});
        permit.permitted[1] = ISignatureTransfer.TokenPermissions({token: lo, amount: amounts[1]});
        permit.nonce = 1;
        permit.deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(IStockPack.TokensNotSortedUnique.selector);
        pack.packWithPermit2("x", permit, "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // renderer admin — the only admin surface
    // ─────────────────────────────────────────────────────────────────────────

    function test_setRenderer_artistOnly_lockOneWay() public {
        StockPackRenderer fresh = new StockPackRenderer(address(pack), address(art), "https://stock-pack.vercel.app");

        vm.expectRevert(IStockPack.NotArtist.selector);
        pack.setRenderer(address(fresh));

        vm.prank(artist);
        vm.expectRevert(IStockPack.RendererNotContract.selector);
        pack.setRenderer(makeAddr("eoa"));

        vm.expectEmit(true, false, false, true);
        emit IStockPack.RendererChanged(address(fresh));
        vm.prank(artist);
        pack.setRenderer(address(fresh));
        assertEq(pack.renderer(), address(fresh));

        vm.expectRevert(IStockPack.NotArtist.selector);
        pack.lockRenderer();

        vm.expectEmit(false, false, false, true);
        emit IStockPack.RendererLocked();
        vm.prank(artist);
        pack.lockRenderer();
        assertTrue(pack.rendererLocked());

        vm.prank(artist);
        vm.expectRevert(IStockPack.RendererIsLocked.selector);
        pack.setRenderer(address(fresh));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // documented sharp edge: _mint to a contract that cannot redeem
    // ─────────────────────────────────────────────────────────────────────────

    function test_mintToNaiveContract_stuckByDesign() public {
        NaivePacker packer = new NaivePacker();
        nvda.mint(address(packer), 1e18);
        packer.approveToken(address(nvda), address(pack));

        address[] memory tokens = new address[](1);
        tokens[0] = address(nvda);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        uint256 id = packer.doPack(address(pack), "Stuck", tokens, amounts);
        // The NFT belongs to a contract with no transfer/unpack passthrough. This is the
        // documented consequence of _mint (no receiver check): integrators MUST be able
        // to call transferFrom/unpackTo themselves.
        assertEq(pack.ownerOf(id), address(packer));
        vm.expectRevert(IStockPack.NotBasketOwner.selector);
        pack.unpack(id); // nobody else can free it either
    }
}
