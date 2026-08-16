// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/NFTRegistry.sol";

contract NFTRegistryHarness is NFTRegistry {
    constructor(address _treasury) NFTRegistry(_treasury) {}

    function tickForTest(uint256 slotIdx) external {
        bytes memory data = abi.encode(_loopID, slotIdx);
        this.progressLoop(data);
    }
}

contract NFTRegistryTest is Test {
    NFTRegistryHarness public reg;
    address public admin    = address(this);
    address public treasury = address(0x1ea1234500000000000000000000000000000001);
    address public buyer    = address(0xBEEF);

    uint256 public releaseInFuture;

    function setUp() public {
        reg = new NFTRegistryHarness(treasury);
        releaseInFuture = block.timestamp + 1 days;
        vm.deal(buyer, 10 ether);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_ConstructorZeroTreasuryReverts() public {
        vm.expectRevert("NFTRegistry: zero treasury");
        new NFTRegistryHarness(address(0));
    }

    function test_InitialState() public view {
        assertEq(reg.treasury(), treasury);
        assertEq(reg.nextCollectionId(), 0);
        assertEq(reg.nextTokenId(), 0);
        assertEq(reg.getReleaseScheduleLength(), 0);
    }

    // ── createCollection ──────────────────────────────────────────────────────

    function test_CreateCollection() public {
        uint256 id = reg.createCollection("CryptoKitties", 1000, 0.01 ether);
        assertEq(id, 0);
        (string memory name, uint256 maxSupply, uint256 minted, uint256 price, bool complete)
            = reg.collections(0);
        assertEq(name, "CryptoKitties");
        assertEq(maxSupply, 1000);
        assertEq(minted, 0);
        assertEq(price, 0.01 ether);
        assertFalse(complete);
    }

    function test_CreateCollectionEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit NFTRegistry.CollectionCreated(0, "CryptoKitties", 1000, 0.01 ether);
        reg.createCollection("CryptoKitties", 1000, 0.01 ether);
    }

    function test_CreateCollectionOnlyAdmin() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        reg.createCollection("x", 1, 0);
    }

    function test_CreateCollectionZeroMaxSupplyReverts() public {
        vm.expectRevert("NFTRegistry: zero maxSupply");
        reg.createCollection("x", 0, 0);
    }

    function test_CreateMultipleCollections() public {
        reg.createCollection("A", 100, 0);
        reg.createCollection("B", 200, 0);
        assertEq(reg.nextCollectionId(), 2);
    }

    // ── scheduleRelease ───────────────────────────────────────────────────────

    function test_ScheduleRelease() public {
        reg.createCollection("A", 100, 0);
        uint256 idx = reg.scheduleRelease(0, 50, releaseInFuture);
        assertEq(idx, 0);
        assertEq(reg.getReleaseScheduleLength(), 1);
    }

    function test_ScheduleReleaseEmitsEvent() public {
        reg.createCollection("A", 100, 0);
        vm.expectEmit(true, true, false, true);
        emit NFTRegistry.ReleaseScheduled(0, 0, 50, releaseInFuture);
        reg.scheduleRelease(0, 50, releaseInFuture);
    }

    function test_ScheduleReleaseUnknownCollectionReverts() public {
        vm.expectRevert("NFTRegistry: unknown collection");
        reg.scheduleRelease(99, 1, releaseInFuture);
    }

    function test_ScheduleReleaseZeroQuantityReverts() public {
        reg.createCollection("A", 100, 0);
        vm.expectRevert("NFTRegistry: zero quantity");
        reg.scheduleRelease(0, 0, releaseInFuture);
    }

    function test_ScheduleReleasePastTimeReverts() public {
        reg.createCollection("A", 100, 0);
        vm.expectRevert("NFTRegistry: release in past");
        reg.scheduleRelease(0, 1, block.timestamp);
    }

    function test_ScheduleReleaseExceedsMaxSupplyReverts() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 60, releaseInFuture);
        vm.expectRevert("NFTRegistry: would exceed max supply");
        reg.scheduleRelease(0, 50, releaseInFuture + 1 days); // 60+50=110 > 100
    }

    function test_ScheduleReleaseOnlyAdmin() public {
        reg.createCollection("A", 100, 0);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        reg.scheduleRelease(0, 10, releaseInFuture);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyNoSchedule() public view {
        (bool ready,) = reg.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_NotReadyBeforeReleaseTime() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 50, releaseInFuture);
        (bool ready,) = reg.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterReleaseTime() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 50, releaseInFuture);
        vm.warp(releaseInFuture);
        (bool ready,) = reg.shouldProgressLoop();
        assertTrue(ready);
    }

    // ── progressLoop ─────────────────────────────────────────────────────────

    function test_ExecuteRelease() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 10, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        (,, uint256 minted,,) = reg.collections(0);
        assertEq(minted, 10);
    }

    function test_TokensOwnedByTreasury() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 5, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(reg.ownerOf(i), treasury);
        }
    }

    function test_TokenCollectionMapping() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 3, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(reg.tokenCollection(i), 0);
        }
    }

    function test_ExecuteReleaseEmitsEvent() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 10, releaseInFuture);
        vm.warp(releaseInFuture);
        vm.expectEmit(true, false, false, false);
        emit NFTRegistry.SupplyReleased(0, 10, 10, releaseInFuture);
        reg.tickForTest(0);
    }

    function test_CannotExecuteTwice() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 10, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.expectRevert("NFTRegistry: already executed");
        reg.tickForTest(0);
    }

    function test_CannotExecuteBeforeReleaseTime() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 10, releaseInFuture);
        // slotIdx 0 exists but releaseTime not reached
        vm.expectRevert("NFTRegistry: too early");
        reg.tickForTest(0);
    }

    function test_StaleLoopIdReverts() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 10, releaseInFuture);
        vm.warp(releaseInFuture);
        bytes memory stale = abi.encode(uint256(99), uint256(0));
        vm.expectRevert("NFTRegistry: stale loop id");
        reg.progressLoop(stale);
    }

    function test_ScheduleReleaseBlockedAfterMinted() public {
        // scheduleRelease counts minted tokens toward the cap —
        // once all tokens are minted, no further scheduling is possible
        reg.createCollection("A", 10, 0);
        reg.scheduleRelease(0, 10, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0); // minted = 10 (all slots used)
        // Now trying to schedule even 1 more should revert
        vm.expectRevert("NFTRegistry: would exceed max supply");
        reg.scheduleRelease(0, 1, releaseInFuture + 1 hours);
    }

    // ── claim ─────────────────────────────────────────────────────────────────

    function test_ClaimToken() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 5, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.prank(buyer);
        reg.claim{value: 0.01 ether}(0);
        assertEq(reg.ownerOf(0), buyer);
        assertTrue(reg.claimed(0));
    }

    function test_ClaimEmitsEvent() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit NFTRegistry.TokenClaimed(0, buyer, 0);
        reg.claim{value: 0.01 ether}(0);
    }

    function test_ClaimInsufficientPaymentReverts() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.prank(buyer);
        vm.expectRevert("NFTRegistry: insufficient payment");
        reg.claim{value: 0.001 ether}(0);
    }

    function test_ClaimNotClaimableReverts() public {
        // tokenId 0 doesn't exist yet
        vm.prank(buyer);
        vm.expectRevert("NFTRegistry: not claimable");
        reg.claim{value: 0}(0);
    }

    function test_ClaimAlreadyClaimedReverts() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.startPrank(buyer);
        reg.claim{value: 0.01 ether}(0);
        vm.expectRevert("NFTRegistry: not claimable"); // ownerOf is now buyer, not treasury
        reg.claim{value: 0.01 ether}(0);
        vm.stopPrank();
    }

    function test_ClaimAccrueFees() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.prank(buyer);
        reg.claim{value: 0.01 ether}(0);
        assertGt(reg.protocolFeeBalance(), 0);
    }

    function test_ClaimRefundsOverpayment() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        uint256 before = buyer.balance;
        vm.prank(buyer);
        reg.claim{value: 0.05 ether}(0); // overpay by 0.04
        assertGt(buyer.balance, before - 0.05 ether); // got refund
    }

    // ── withdrawProtocolFees ──────────────────────────────────────────────────

    function test_WithdrawProtocolFees() public {
        reg.createCollection("A", 100, 0.01 ether);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.prank(buyer);
        reg.claim{value: 0.01 ether}(0);
        uint256 fees = reg.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xF33);
        reg.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
        assertEq(reg.protocolFeeBalance(), 0);
    }

    function test_WithdrawProtocolFeesOnlyAdmin() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        reg.withdrawProtocolFees(address(0xF33));
    }

    // ── setTreasury ───────────────────────────────────────────────────────────

    function test_SetTreasury() public {
        address newTreasury = address(0x4E455700000000000000000000000000000000e1);
        reg.setTreasury(newTreasury);
        assertEq(reg.treasury(), newTreasury);
    }

    function test_SetTreasuryZeroReverts() public {
        vm.expectRevert("NFTRegistry: zero treasury");
        reg.setTreasury(address(0));
    }

    // ── multi-release ─────────────────────────────────────────────────────────

    function test_MultipleReleasesSequential() public {
        reg.createCollection("A", 100, 0);
        reg.scheduleRelease(0, 30, releaseInFuture);
        reg.scheduleRelease(0, 30, releaseInFuture + 1 hours);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.warp(releaseInFuture + 1 hours);
        reg.tickForTest(1);
        (,, uint256 minted,,) = reg.collections(0);
        assertEq(minted, 60);
        assertEq(reg.nextTokenId(), 60);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_ClaimFeeCalculation(uint64 price, uint64 payment) public {
        vm.assume(price > 0 && payment >= price);
        reg.createCollection("A", 100, price);
        reg.scheduleRelease(0, 1, releaseInFuture);
        vm.warp(releaseInFuture);
        reg.tickForTest(0);
        vm.deal(buyer, uint256(payment) + 1 ether);
        vm.prank(buyer);
        reg.claim{value: payment}(0);
        uint256 expectedFee = (uint256(price) * 200) / 10_000;
        assertEq(reg.protocolFeeBalance(), expectedFee);
    }

    receive() external payable {}
}
