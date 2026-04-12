// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/SponsorAuction.sol";

contract SponsorAuctionTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    SponsorAuction public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public slotReceiver;
    address public controller1;

    uint256 constant AUCTION_DURATION = 120;
    uint256 constant SPONSORSHIP_PERIOD = 3600;
    uint256 constant MIN_BID = 0.001 ether;
    uint256 constant MIN_INCREMENT_BPS = 500; // 5%
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint256 constant GAS_PRICE = 20 gwei;

    receive() external payable {}

    function setUp() public {
        proxyAdmin = vm.addr(99);
        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        carol = vm.addr(0xCA20A);
        slotReceiver = vm.addr(0x510E);
        controller1 = vm.addr(0xC0DE);
        admin = address(this);

        vm.deal(admin, 1000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(controller1, 100 ether);

        AutoLoop autoLoopImpl = new AutoLoop();
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(string)", "0.0.1")
        );
        autoLoop = AutoLoop(address(autoLoopProxy));

        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(address)", admin)
        );
        registry = AutoLoopRegistry(address(registryProxy));

        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();
        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            proxyAdmin,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(autoLoop),
                address(registry),
                admin
            )
        );
        registrar = AutoLoopRegistrar(address(registrarProxy));

        registry.setRegistrar(address(registrar));
        autoLoop.setRegistrar(address(registrar));

        game = new SponsorAuction(
            AUCTION_DURATION,
            SPONSORSHIP_PERIOD,
            MIN_BID,
            MIN_INCREMENT_BPS,
            PROTOCOL_RAKE_BPS,
            slotReceiver
        );
        registrar.registerAutoLoopFor(address(game), 2_000_000);

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        registrar.deposit{value: 10 ether}(address(game));
    }

    // ===============================================================
    //  Section 1 — ERC165 / initial state
    // ===============================================================

    function test_SupportsAutoLoopInterface() public view {
        assertTrue(
            game.supportsInterface(type(AutoLoopCompatibleInterface).interfaceId)
        );
    }

    function test_InitialState() public view {
        assertEq(game.currentAuctionId(), 1, "first auction id is 1");
        assertEq(game.highestBid(), 0);
        assertEq(game.highestBidder(), address(0));
        assertTrue(game.auctionOpen());
        assertEq(game.currentSponsor(), address(0));
        assertFalse(game.sponsorshipActive());
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.slotReceiver(), slotReceiver);
    }

    function test_Immutables() public view {
        assertEq(game.auctionDuration(), AUCTION_DURATION);
        assertEq(game.sponsorshipPeriod(), SPONSORSHIP_PERIOD);
        assertEq(game.minBid(), MIN_BID);
        assertEq(game.minIncrementBps(), MIN_INCREMENT_BPS);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
    }

    function test_ConstructorSetsCloseTime() public view {
        assertEq(game.auctionClosesAt(), game.auctionStartedAt() + AUCTION_DURATION);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroDuration() public {
        vm.expectRevert("SponsorAuction: duration=0");
        new SponsorAuction(
            0,
            SPONSORSHIP_PERIOD,
            MIN_BID,
            MIN_INCREMENT_BPS,
            PROTOCOL_RAKE_BPS,
            slotReceiver
        );
    }

    function test_ConstructorRejectsZeroPeriod() public {
        vm.expectRevert("SponsorAuction: period=0");
        new SponsorAuction(
            AUCTION_DURATION,
            0,
            MIN_BID,
            MIN_INCREMENT_BPS,
            PROTOCOL_RAKE_BPS,
            slotReceiver
        );
    }

    function test_ConstructorRejectsZeroMinBid() public {
        vm.expectRevert("SponsorAuction: minBid=0");
        new SponsorAuction(
            AUCTION_DURATION,
            SPONSORSHIP_PERIOD,
            0,
            MIN_INCREMENT_BPS,
            PROTOCOL_RAKE_BPS,
            slotReceiver
        );
    }

    function test_ConstructorRejectsZeroIncrement() public {
        vm.expectRevert("SponsorAuction: increment=0");
        new SponsorAuction(
            AUCTION_DURATION,
            SPONSORSHIP_PERIOD,
            MIN_BID,
            0,
            PROTOCOL_RAKE_BPS,
            slotReceiver
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("SponsorAuction: rake > 20%");
        new SponsorAuction(
            AUCTION_DURATION,
            SPONSORSHIP_PERIOD,
            MIN_BID,
            MIN_INCREMENT_BPS,
            2001,
            slotReceiver
        );
    }

    function test_ConstructorRejectsZeroReceiver() public {
        vm.expectRevert("SponsorAuction: receiver=0");
        new SponsorAuction(
            AUCTION_DURATION,
            SPONSORSHIP_PERIOD,
            MIN_BID,
            MIN_INCREMENT_BPS,
            PROTOCOL_RAKE_BPS,
            address(0)
        );
    }

    // ===============================================================
    //  Section 3 — Bidding
    // ===============================================================

    function test_FirstBidRequiresMinBid() public {
        vm.prank(alice);
        vm.expectRevert("SponsorAuction: bid too low");
        game.bid{value: MIN_BID - 1}();
    }

    function test_FirstBidSucceeds() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        assertEq(game.highestBidder(), alice);
        assertEq(game.highestBid(), MIN_BID);
    }

    function test_SubsequentBidRequiresIncrement() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();

        uint256 needed = game.currentMinBid();
        vm.prank(bob);
        vm.expectRevert("SponsorAuction: bid too low");
        game.bid{value: needed - 1}();
    }

    function test_SecondBidRefundsFirstBidder() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();

        uint256 second = game.currentMinBid();
        vm.prank(bob);
        game.bid{value: second}();

        assertEq(game.highestBidder(), bob);
        assertEq(game.highestBid(), second);
        assertEq(game.refunds(alice), MIN_BID);
    }

    function test_AliceCanClaimRefund() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        uint256 second = game.currentMinBid();
        vm.prank(bob);
        game.bid{value: second}();

        uint256 before = alice.balance;
        vm.prank(alice);
        game.claimRefund();
        assertEq(alice.balance - before, MIN_BID);
    }

    function test_ClaimRefundRejectsZero() public {
        vm.prank(alice);
        vm.expectRevert("SponsorAuction: no refund");
        game.claimRefund();
    }

    function test_BidRejectsAfterClose() public {
        vm.warp(game.auctionClosesAt());
        vm.prank(alice);
        vm.expectRevert("SponsorAuction: auction expired");
        game.bid{value: MIN_BID}();
    }

    function test_BidEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(game));
        emit SponsorAuction.BidPlaced(1, alice, MIN_BID);
        vm.prank(alice);
        game.bid{value: MIN_BID}();
    }

    // ===============================================================
    //  Section 4 — Auction close / loop progression
    // ===============================================================

    function test_ShouldProgressFalseBeforeClose() public view {
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueAtClose() public {
        vm.warp(game.auctionClosesAt());
        (bool ready, bytes memory data) = game.shouldProgressLoop();
        assertTrue(ready);
        uint256 auctionId = abi.decode(data, (uint256));
        assertEq(auctionId, 1);
    }

    function test_CloseWithWinner() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());

        bytes memory data = abi.encode(game.currentAuctionId());
        game.progressLoop(data);

        assertEq(game.currentSponsor(), alice);
        assertEq(game.totalAuctionsClosed(), 1);

        uint256 expectedRake = (MIN_BID * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPayout = MIN_BID - expectedRake;
        assertEq(game.protocolFeeBalance(), expectedRake);
        assertEq(game.refunds(slotReceiver), expectedPayout);
        assertTrue(game.sponsorshipActive());
    }

    function test_CloseWithNoBidsEmitsNoBidsEvent() public {
        vm.warp(game.auctionClosesAt());

        vm.expectEmit(true, false, false, false, address(game));
        emit SponsorAuction.AuctionClosedNoBids(1);

        bytes memory data = abi.encode(game.currentAuctionId());
        game.progressLoop(data);
    }

    function test_CloseImmediatelyOpensNextAuction() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());

        bytes memory data = abi.encode(game.currentAuctionId());
        game.progressLoop(data);

        assertEq(game.currentAuctionId(), 2);
        assertTrue(game.auctionOpen());
        assertEq(game.highestBid(), 0);
        assertEq(game.highestBidder(), address(0));
    }

    function test_CloseRejectsTooSoon() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();

        bytes memory data = abi.encode(game.currentAuctionId());
        vm.expectRevert("SponsorAuction: too soon");
        game.progressLoop(data);
    }

    function test_CloseRejectsStaleId() public {
        vm.warp(game.auctionClosesAt());
        bytes memory data = abi.encode(uint256(999));
        vm.expectRevert("SponsorAuction: stale id");
        game.progressLoop(data);
    }

    function test_CloseEmitsEvent() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());

        uint256 rake = (MIN_BID * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 payout = MIN_BID - rake;

        vm.expectEmit(true, true, false, true, address(game));
        emit SponsorAuction.AuctionClosed(1, alice, MIN_BID, payout, rake);

        bytes memory data = abi.encode(game.currentAuctionId());
        game.progressLoop(data);
    }

    // ===============================================================
    //  Section 5 — Sponsorship lifecycle
    // ===============================================================

    function test_SponsorshipActivatesAfterWin() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());
        game.progressLoop(abi.encode(game.currentAuctionId()));

        assertTrue(game.sponsorshipActive());
        assertEq(game.currentSponsor(), alice);
    }

    function test_SponsorshipExpires() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        uint256 closeTime = game.auctionClosesAt();
        vm.warp(closeTime);
        game.progressLoop(abi.encode(game.currentAuctionId()));

        // Warp past expiry
        vm.warp(closeTime + SPONSORSHIP_PERIOD + 1);
        assertFalse(game.sponsorshipActive());
    }

    // ===============================================================
    //  Section 6 — Slot receiver claims payout
    // ===============================================================

    function test_SlotReceiverClaimsPayout() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());
        game.progressLoop(abi.encode(game.currentAuctionId()));

        uint256 expectedPayout = game.refunds(slotReceiver);
        uint256 before = slotReceiver.balance;
        vm.prank(slotReceiver);
        game.claimRefund();
        assertEq(slotReceiver.balance - before, expectedPayout);
    }

    // ===============================================================
    //  Section 7 — Multiple sequential auctions
    // ===============================================================

    function test_MultipleAuctions() public {
        uint256 ts = block.timestamp;
        for (uint256 i = 0; i < 5; i++) {
            // Alice bids
            vm.prank(alice);
            game.bid{value: game.currentMinBid()}();

            // Close
            ts += AUCTION_DURATION;
            vm.warp(ts);
            game.progressLoop(abi.encode(game.currentAuctionId()));
        }
        assertEq(game.totalAuctionsClosed(), 5);
        assertEq(game.currentAuctionId(), 6);
    }

    // ===============================================================
    //  Section 8 — Admin
    // ===============================================================

    function test_SetSlotReceiver() public {
        address newReceiver = vm.addr(0xFFFFFF);
        game.setSlotReceiver(newReceiver);
        assertEq(game.slotReceiver(), newReceiver);
    }

    function test_SetSlotReceiverRejectsNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        game.setSlotReceiver(alice);
    }

    function test_SetSlotReceiverRejectsZero() public {
        vm.expectRevert("SponsorAuction: receiver=0");
        game.setSlotReceiver(address(0));
    }

    function test_WithdrawProtocolFees() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());
        game.progressLoop(abi.encode(game.currentAuctionId()));

        uint256 fee = game.protocolFeeBalance();
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, fee);
        assertEq(admin.balance - before, fee);
    }

    // ===============================================================
    //  Section 9 — AutoLoop integration (non-VRF path)
    // ===============================================================

    function test_ProgressLoopThroughAutoLoop() public {
        vm.prank(alice);
        game.bid{value: MIN_BID}();
        vm.warp(game.auctionClosesAt());
        vm.roll(block.number + 1);

        bytes memory data = abi.encode(uint256(1));
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        autoLoop.progressLoop(address(game), data);

        assertEq(game.currentSponsor(), alice);
    }

    // ===============================================================
    //  Section 10 — Fuzz tests
    // ===============================================================

    /// @dev Bid amounts monotonically increase with each accepted bid.
    function testFuzz_BidsMonotonic(uint96 first, uint96 second) public {
        first = uint96(bound(uint256(first), MIN_BID, 10 ether));
        vm.deal(alice, uint256(first));
        vm.prank(alice);
        game.bid{value: uint256(first)}();

        uint256 needed = game.currentMinBid();
        second = uint96(bound(uint256(second), needed, 20 ether));
        vm.deal(bob, uint256(second));
        vm.prank(bob);
        game.bid{value: uint256(second)}();

        assertGt(game.highestBid(), first);
        assertEq(game.highestBidder(), bob);
    }

    /// @dev Protocol rake + slot receiver payout always equal the winning bid.
    function testFuzz_CloseAccounting(uint96 bidAmount) public {
        bidAmount = uint96(bound(uint256(bidAmount), MIN_BID, 10 ether));
        vm.deal(alice, uint256(bidAmount));
        vm.prank(alice);
        game.bid{value: uint256(bidAmount)}();

        vm.warp(game.auctionClosesAt());
        game.progressLoop(abi.encode(game.currentAuctionId()));

        uint256 rake = game.protocolFeeBalance();
        uint256 payout = game.refunds(slotReceiver);
        assertEq(rake + payout, uint256(bidAmount));
    }
}
