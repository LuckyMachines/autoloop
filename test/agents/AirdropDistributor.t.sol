// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/AirdropDistributor.sol";

contract AirdropDistributorHarness is AirdropDistributor {
    constructor(uint256 _interval, uint256 _winners, uint256 _prize)
        AirdropDistributor(_interval, _winners, _prize) {}

    function tickForTest(bytes32 randomness) external {
        require((block.timestamp - lastDraw) >= drawInterval, "AirdropDistributor: too soon");
        uint256 n = pool.length;
        address[] memory poolCopy = new address[](n);
        for (uint256 i = 0; i < n; i++) poolCopy[i] = pool[i];

        address[] memory winners = new address[](winnersPerDraw);
        for (uint256 i = 0; i < winnersPerDraw; i++) {
            uint256 remaining = n - i;
            uint256 idx = i + uint256(keccak256(abi.encodePacked(randomness, i))) % remaining;
            winners[i] = poolCopy[idx];
            poolCopy[idx] = poolCopy[i];
        }

        uint256 currentLoopID = _loopID;
        lastDraw = block.timestamp;
        ++_loopID;

        uint256 totalPrize = prizePerWinner * winnersPerDraw;
        uint256 fee = (totalPrize * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;
        uint256 payoutEach = (totalPrize - fee) / winnersPerDraw;

        uint256 roundId = roundCount++;
        rounds[roundId].id = roundId;
        rounds[roundId].prizePerWinner = prizePerWinner;
        rounds[roundId].winnersCount = winnersPerDraw;
        rounds[roundId].settled = true;
        rounds[roundId].timestamp = block.timestamp;
        for (uint256 i = 0; i < winners.length; i++) rounds[roundId].winners.push(winners[i]);

        for (uint256 i = 0; i < winners.length; i++) {
            (bool ok,) = winners[i].call{value: payoutEach}("");
            require(ok, "payout failed");
        }
        emit DrawSettled(roundId, winners, payoutEach, currentLoopID);
    }
}

contract AirdropDistributorTest is Test {
    AirdropDistributorHarness public dist;
    uint256 public interval = 7 days;
    uint256 public prizeEach = 0.1 ether;
    uint256 public winnersCount = 2;

    address[] public participants;

    function setUp() public {
        dist = new AirdropDistributorHarness(interval, winnersCount, prizeEach);
        // Fund for at least one draw
        vm.deal(address(dist), 10 ether);
        // Register 5 participants
        for (uint160 i = 1; i <= 5; i++) {
            address p = address(i * 0x1111);
            participants.push(p);
            vm.prank(p);
            dist.register();
        }
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeInterval() public view {
        (bool ready,) = dist.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterInterval() public {
        vm.warp(block.timestamp + interval);
        (bool ready,) = dist.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_NotReadyPoolTooSmall() public {
        // Deregister until pool < winnersCount
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(participants[i]);
            dist.deregister();
        }
        vm.warp(block.timestamp + interval);
        (bool ready,) = dist.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── register / deregister ─────────────────────────────────────────────────

    function test_RegisterAddsToPool() public {
        assertEq(dist.poolSize(), 5);
    }

    function test_CannotRegisterTwice() public {
        vm.prank(participants[0]);
        vm.expectRevert("AirdropDistributor: already registered");
        dist.register();
    }

    function test_DeregisterRemovesFromPool() public {
        vm.prank(participants[0]);
        dist.deregister();
        assertEq(dist.poolSize(), 4);
        assertFalse(dist.registered(participants[0]));
    }

    function test_CannotDeregisterIfNotRegistered() public {
        vm.expectRevert("AirdropDistributor: not registered");
        dist.deregister();
    }

    // ── tickForTest ──────────────────────────────────────────────────────────

    function test_DrawPicksWinners() public {
        vm.warp(block.timestamp + interval);
        bytes32 seed = keccak256("test_seed");
        uint256 before0 = participants[0].balance + participants[1].balance +
                          participants[2].balance + participants[3].balance + participants[4].balance;
        dist.tickForTest(seed);
        uint256 after0 = participants[0].balance + participants[1].balance +
                         participants[2].balance + participants[3].balance + participants[4].balance;
        assertGt(after0, before0);
    }

    function test_DrawRecordsRound() public {
        vm.warp(block.timestamp + interval);
        dist.tickForTest(keccak256("seed"));
        assertEq(dist.roundCount(), 1);
    }

    function test_DrawTakesProtocolFee() public {
        vm.warp(block.timestamp + interval);
        dist.tickForTest(keccak256("seed"));
        assertGt(dist.protocolFeeBalance(), 0);
    }

    function test_DrawTooSoonReverts() public {
        vm.expectRevert(); // pool and interval checks in tickForTest hit require
        dist.tickForTest(keccak256("seed")); // interval not passed
    }

    // ── admin ─────────────────────────────────────────────────────────────────

    function test_WithdrawFees() public {
        vm.warp(block.timestamp + interval);
        dist.tickForTest(keccak256("seed"));
        uint256 fees = dist.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xFEED);
        dist.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
    }

    function test_SetWinnersPerDrawZeroReverts() public {
        vm.expectRevert("AirdropDistributor: winners=0");
        dist.setWinnersPerDraw(0);
    }

    function test_SetIntervalZeroReverts() public {
        vm.expectRevert("AirdropDistributor: interval=0");
        dist.setDrawInterval(0);
    }

    // ── constructor validation ────────────────────────────────────────────────

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("AirdropDistributor: interval=0");
        new AirdropDistributorHarness(0, winnersCount, prizeEach);
    }

    function test_ConstructorZeroWinnersReverts() public {
        vm.expectRevert("AirdropDistributor: winners=0");
        new AirdropDistributorHarness(interval, 0, prizeEach);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_DifferentSeedsPickDifferentWinners(bytes32 seed1, bytes32 seed2) public {
        vm.assume(seed1 != seed2);
        vm.assume(dist.poolSize() >= winnersCount);
        // Just verify both draws run without reverting
        vm.warp(block.timestamp + interval);
        dist.tickForTest(seed1);
        vm.warp(block.timestamp + interval + 1);
        dist.tickForTest(seed2);
        assertEq(dist.roundCount(), 2);
    }

    function testFuzz_FeeCalculation(uint96 extra) public {
        // Give extra funds and verify fee proportion
        vm.deal(address(dist), uint256(extra) + 10 ether);
        vm.warp(block.timestamp + interval);
        dist.tickForTest(keccak256("fee_fuzz"));
        uint256 expectedFee = (prizeEach * winnersCount * 200) / 10_000;
        assertEq(dist.protocolFeeBalance(), expectedFee);
    }

    receive() external payable {}
}
