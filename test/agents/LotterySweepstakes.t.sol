// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/LotterySweepstakes.sol";

contract LotterySweepstakesHarness is LotterySweepstakes {
    constructor(uint256 _price, uint256 _interval)
        LotterySweepstakes(_price, _interval) {}

    function tickForTest(bytes32 randomness) external {
        require(currentEntrants.length > 0, "LotterySweepstakes: no entrants");
        require((block.timestamp - lastDraw) >= roundInterval, "LotterySweepstakes: too soon");

        lastDraw = block.timestamp;
        uint256 currentLoopID = _loopID;
        ++_loopID;

        // Build ticket array and pick winner
        uint256 totalTickets;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalTickets += ticketCount[currentEntrants[i]];
        }

        uint256 winnerIdx = uint256(randomness) % totalTickets;
        uint256 cumulative;
        address winner;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += ticketCount[currentEntrants[i]];
            if (winnerIdx < cumulative) {
                winner = currentEntrants[i];
                break;
            }
        }

        uint256 pool = address(this).balance - protocolFeeBalance;
        uint256 fee = (pool * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;
        uint256 prize = pool - fee;

        uint256 roundId = roundCount++;
        rounds[roundId] = Round({
            id: roundId,
            winner: winner,
            prize: prize,
            entrantCount: currentEntrants.length,
            timestamp: block.timestamp,
            loopID: currentLoopID
        });

        for (uint256 i = 0; i < currentEntrants.length; i++) ticketCount[currentEntrants[i]] = 0;
        delete currentEntrants;

        (bool ok,) = winner.call{value: prize}("");
        require(ok, "LotterySweepstakes: prize transfer failed");
        emit RoundSettled(roundId, winner, prize, currentLoopID);
    }
}

contract LotterySweepstakesTest is Test {
    LotterySweepstakesHarness public lottery;
    uint256 public ticketPrice = 0.01 ether;
    uint256 public roundInterval = 7 days;

    address public alice = address(0xA1);
    address public bob   = address(0xB2);
    address public carol = address(0xC3);

    function setUp() public {
        lottery = new LotterySweepstakesHarness(ticketPrice, roundInterval);
        vm.deal(alice, 1 ether);
        vm.deal(bob,   1 ether);
        vm.deal(carol, 1 ether);
    }

    function _buyTickets(address who, uint256 count) internal {
        vm.prank(who);
        lottery.buyTickets{value: ticketPrice * count}(count);
    }

    // ── buyTickets ────────────────────────────────────────────────────────────

    function test_BuyTicketsAddsEntrant() public {
        _buyTickets(alice, 1);
        assertEq(lottery.entrantCount(), 1);
        assertEq(lottery.ticketCount(alice), 1);
    }

    function test_BuyMultipleTickets() public {
        _buyTickets(alice, 3);
        assertEq(lottery.ticketCount(alice), 3);
        assertEq(lottery.entrantCount(), 1); // still one entrant
    }

    function test_BuyTicketsWrongValueReverts() public {
        vm.prank(alice);
        vm.expectRevert("LotterySweepstakes: wrong value");
        lottery.buyTickets{value: ticketPrice - 1}(1);
    }

    function test_BuyTicketsZeroCountReverts() public {
        vm.prank(alice);
        vm.expectRevert("LotterySweepstakes: count=0");
        lottery.buyTickets{value: 0}(0);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeInterval() public {
        _buyTickets(alice, 1);
        (bool ready,) = lottery.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterInterval() public {
        _buyTickets(alice, 1);
        vm.warp(block.timestamp + roundInterval);
        (bool ready,) = lottery.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_NotReadyNoEntrants() public {
        vm.warp(block.timestamp + roundInterval);
        (bool ready,) = lottery.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── tickForTest ──────────────────────────────────────────────────────────

    function test_DrawPicksAWinner() public {
        _buyTickets(alice, 1);
        _buyTickets(bob, 1);
        vm.warp(block.timestamp + roundInterval);
        uint256 beforeAlice = alice.balance;
        uint256 beforeBob = bob.balance;
        lottery.tickForTest(keccak256("seed"));
        // One of alice or bob has more ETH
        assertTrue(alice.balance > beforeAlice || bob.balance > beforeBob);
    }

    function test_DrawResetsEntrants() public {
        _buyTickets(alice, 1);
        vm.warp(block.timestamp + roundInterval);
        lottery.tickForTest(keccak256("seed"));
        assertEq(lottery.entrantCount(), 0);
        assertEq(lottery.ticketCount(alice), 0);
    }

    function test_DrawRecordsRound() public {
        _buyTickets(alice, 1);
        vm.warp(block.timestamp + roundInterval);
        lottery.tickForTest(keccak256("seed"));
        assertEq(lottery.roundCount(), 1);
        (uint256 id, address winner,,,,) = lottery.rounds(0);
        assertEq(id, 0);
        assertEq(winner, alice); // only entrant always wins
    }

    function test_DrawTakesProtocolFee() public {
        _buyTickets(alice, 1);
        vm.warp(block.timestamp + roundInterval);
        lottery.tickForTest(keccak256("seed"));
        assertGt(lottery.protocolFeeBalance(), 0);
    }

    function test_TooSoonReverts() public {
        _buyTickets(alice, 1);
        vm.expectRevert("LotterySweepstakes: too soon");
        lottery.tickForTest(keccak256("seed"));
    }

    function test_NoEntrantsReverts() public {
        vm.warp(block.timestamp + roundInterval);
        vm.expectRevert("LotterySweepstakes: no entrants");
        lottery.tickForTest(keccak256("seed"));
    }

    function test_MultipleRoundsWork() public {
        for (uint256 i = 0; i < 3; i++) {
            _buyTickets(alice, 1);
            _buyTickets(bob, 1);
            vm.warp(block.timestamp + roundInterval + 1);
            lottery.tickForTest(keccak256(abi.encode(i)));
        }
        assertEq(lottery.roundCount(), 3);
    }

    // ── weighted tickets ─────────────────────────────────────────────────────

    function test_SoleEntrantAlwaysWins() public {
        _buyTickets(alice, 5);
        vm.warp(block.timestamp + roundInterval);
        uint256 before = alice.balance;
        lottery.tickForTest(keccak256("any_seed"));
        assertGt(alice.balance, before);
    }

    // ── admin ─────────────────────────────────────────────────────────────────

    function test_WithdrawFees() public {
        _buyTickets(alice, 1);
        vm.warp(block.timestamp + roundInterval);
        lottery.tickForTest(keccak256("seed"));
        uint256 fees = lottery.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xFEED);
        lottery.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
    }

    function test_SetTicketPriceZeroReverts() public {
        vm.expectRevert("LotterySweepstakes: ticketPrice=0");
        lottery.setTicketPrice(0);
    }

    function test_SetRoundIntervalZeroReverts() public {
        vm.expectRevert("LotterySweepstakes: interval=0");
        lottery.setRoundInterval(0);
    }

    // ── constructor validation ────────────────────────────────────────────────

    function test_ConstructorZeroPriceReverts() public {
        vm.expectRevert("LotterySweepstakes: ticketPrice=0");
        new LotterySweepstakesHarness(0, roundInterval);
    }

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("LotterySweepstakes: interval=0");
        new LotterySweepstakesHarness(ticketPrice, 0);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_FeeNeverExceedsPrize(uint8 ticketsToBuy) public {
        vm.assume(ticketsToBuy > 0 && ticketsToBuy <= 10);
        vm.deal(alice, uint256(ticketsToBuy) * ticketPrice + 1 ether);
        _buyTickets(alice, ticketsToBuy);
        vm.warp(block.timestamp + roundInterval);
        uint256 poolBefore = address(lottery).balance;
        lottery.tickForTest(keccak256("fuzz"));
        uint256 fees = lottery.protocolFeeBalance();
        assertLe(fees, poolBefore);
    }

    function testFuzz_WinnerIsAlwaysAnEntrant(bytes32 seed) public {
        _buyTickets(alice, 1);
        _buyTickets(bob, 1);
        _buyTickets(carol, 1);
        vm.warp(block.timestamp + roundInterval);
        lottery.tickForTest(seed);
        (,address winner,,,,) = lottery.rounds(0);
        assertTrue(winner == alice || winner == bob || winner == carol);
    }

    receive() external payable {}
}
