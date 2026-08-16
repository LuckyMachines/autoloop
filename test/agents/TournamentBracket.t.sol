// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/TournamentBracket.sol";

contract TournamentBracketHarness is TournamentBracket {
    constructor(uint256 _interval, uint8 _max, uint256 _fee)
        TournamentBracket(_interval, _max, _fee) {}

    function seedBracketForTest(bytes32 randomness) external {
        require(phase == Phase.Active, "not active");
        _seedBracket(randomness);
        lastRoundTime = block.timestamp;
        ++_loopID;
    }

    function resolveRoundForTest(bytes32 randomness) external {
        require(phase == Phase.Active, "not active");
        require(activePlayers > 1, "only one player");
        require((block.timestamp - lastRoundTime) >= roundInterval, "too soon");
        lastRoundTime = block.timestamp;
        ++_loopID;
        _resolveRound(randomness);
    }
}

contract TournamentBracketTest is Test {
    TournamentBracketHarness public tb;
    uint256 public interval  = 1 hours;
    uint8   public maxP      = 4;
    uint256 public entryFee  = 0.01 ether;

    address[4] public players;

    function setUp() public {
        tb = new TournamentBracketHarness(interval, maxP, entryFee);
        for (uint256 i = 0; i < 4; i++) {
            players[i] = address(uint160(0xA000 + i));
            vm.deal(players[i], 1 ether);
        }
    }

    function _registerAll() internal {
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(players[i]);
            tb.register{value: entryFee}();
        }
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("TournamentBracket: interval=0");
        new TournamentBracketHarness(0, 4, entryFee);
    }

    function test_ConstructorInvalidMaxPlayersReverts() public {
        vm.expectRevert("TournamentBracket: maxPlayers must be 4, 8, or 16");
        new TournamentBracketHarness(interval, 5, entryFee);
    }

    function test_ConstructorMaxPlayers4() public {
        TournamentBracketHarness t = new TournamentBracketHarness(interval, 4, entryFee);
        assertEq(t.maxPlayers(), 4);
    }

    function test_ConstructorMaxPlayers8() public {
        TournamentBracketHarness t = new TournamentBracketHarness(interval, 8, entryFee);
        assertEq(t.maxPlayers(), 8);
    }

    function test_InitialState() public view {
        assertEq(uint8(tb.phase()), uint8(TournamentBracket.Phase.Registration));
        assertEq(tb.playerCount(), 0);
        assertEq(tb.activePlayers(), 0);
    }

    // ── register ──────────────────────────────────────────────────────────────

    function test_Register() public {
        vm.prank(players[0]);
        tb.register{value: entryFee}();
        assertEq(tb.playerCount(), 1);
        assertTrue(tb.registered(players[0]));
    }

    function test_RegisterEmitsEvent() public {
        vm.prank(players[0]);
        vm.expectEmit(true, false, false, true);
        emit TournamentBracket.PlayerRegistered(players[0], 0);
        tb.register{value: entryFee}();
    }

    function test_RegisterAddsPrizePot() public {
        vm.prank(players[0]);
        tb.register{value: entryFee}();
        assertEq(tb.prizePool(), entryFee);
    }

    function test_RegisterDuplicateReverts() public {
        vm.prank(players[0]);
        tb.register{value: entryFee}();
        vm.prank(players[0]);
        vm.expectRevert("TournamentBracket: already registered");
        tb.register{value: entryFee}();
    }

    function test_RegisterWhenFullReverts() public {
        _registerAll();
        address extra = address(0xEEEE);
        vm.deal(extra, 1 ether);
        vm.prank(extra);
        vm.expectRevert("TournamentBracket: full");
        tb.register{value: entryFee}();
    }

    function test_RegisterInsufficientFeeReverts() public {
        vm.prank(players[0]);
        vm.expectRevert("TournamentBracket: insufficient entry fee");
        tb.register{value: entryFee - 1}();
    }

    function test_RegisterRefundsOverpayment() public {
        uint256 before = players[0].balance;
        vm.prank(players[0]);
        tb.register{value: entryFee + 0.5 ether}();
        assertGt(players[0].balance, before - entryFee - 0.5 ether);
    }

    function test_RegisterNotRegistrationPhaseReverts() public {
        _registerAll();
        tb.startTournament();
        address extra = address(0xEEEE);
        vm.deal(extra, 1 ether);
        vm.prank(extra);
        vm.expectRevert("TournamentBracket: not registration");
        tb.register{value: entryFee}();
    }

    // ── startTournament ───────────────────────────────────────────────────────

    function test_StartTournament() public {
        _registerAll();
        tb.startTournament();
        assertEq(uint8(tb.phase()), uint8(TournamentBracket.Phase.Active));
        assertEq(tb.activePlayers(), 4);
    }

    function test_StartTournamentEmitsEvent() public {
        _registerAll();
        vm.expectEmit(false, false, false, true);
        emit TournamentBracket.TournamentStarted(4, entryFee * 4);
        tb.startTournament();
    }

    function test_StartTournamentNotFullReverts() public {
        vm.prank(players[0]);
        tb.register{value: entryFee}();
        vm.expectRevert("TournamentBracket: not full");
        tb.startTournament();
    }

    function test_StartTournamentAlreadyStartedReverts() public {
        _registerAll();
        tb.startTournament();
        vm.expectRevert("TournamentBracket: already started");
        tb.startTournament();
    }

    function test_StartTournamentOnlyAdmin() public {
        _registerAll();
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        tb.startTournament();
    }

    // ── withdrawIfNoStart ─────────────────────────────────────────────────────

    function test_WithdrawIfNoStart() public {
        vm.prank(players[0]);
        tb.register{value: entryFee}();
        uint256 before = players[0].balance;
        vm.prank(players[0]);
        tb.withdrawIfNoStart();
        assertEq(players[0].balance, before + entryFee);
        assertFalse(tb.registered(players[0]));
    }

    function test_WithdrawIfNoStartAfterStartReverts() public {
        _registerAll();
        tb.startTournament();
        vm.prank(players[0]);
        vm.expectRevert("TournamentBracket: tournament started");
        tb.withdrawIfNoStart();
    }

    // ── seedBracketForTest ────────────────────────────────────────────────────

    function test_SeedBracketPopulatesSlots() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        // All 4 slots should have players
        uint256 filled;
        for (uint256 i = 0; i < 4; i++) {
            if (tb.bracket(i) != address(0)) filled++;
        }
        assertEq(filled, 4);
    }

    function test_SeedBracketContainsAllPlayers() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        // Each registered player appears exactly once
        for (uint256 p = 0; p < 4; p++) {
            uint256 count;
            for (uint256 s = 0; s < 4; s++) {
                if (tb.bracket(s) == players[p]) count++;
            }
            assertEq(count, 1);
        }
    }

    // ── resolveRoundForTest ───────────────────────────────────────────────────

    function test_ResolveRoundEliminatesHalfPlayers() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("round1"));
        assertEq(tb.activePlayers(), 2);
    }

    function test_ResolveRoundRecordsMatchHistory() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("round1"));
        assertEq(tb.matchHistoryLength(), 2); // 4 players = 2 matches in R1
    }

    function test_ResolveRoundEmitsEvent() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        vm.recordLogs();
        tb.resolveRoundForTest(keccak256("round1"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == TournamentBracket.RoundComplete.selector) found = true;
        }
        assertTrue(found);
    }

    function test_TooSoonReverts() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.expectRevert("too soon");
        tb.resolveRoundForTest(keccak256("round1"));
    }

    // ── full tournament (4 players) ───────────────────────────────────────────

    function test_FullTournamentCompletesWithChampion() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));

        // Round 1: 4 → 2
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));
        assertEq(tb.activePlayers(), 2);
        assertEq(uint8(tb.phase()), uint8(TournamentBracket.Phase.Active));

        // Round 2: 2 → champion
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r2"));
        assertEq(uint8(tb.phase()), uint8(TournamentBracket.Phase.Complete));
        assertNotEq(tb.champion(), address(0));
    }

    function test_ChampionIsARegisteredPlayer() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r2"));

        address champion = tb.champion();
        bool isPlayer;
        for (uint256 i = 0; i < 4; i++) {
            if (players[i] == champion) isPlayer = true;
        }
        assertTrue(isPlayer);
    }

    function test_ChampionReceivesPrize() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));

        uint256[4] memory before;
        for (uint256 i = 0; i < 4; i++) before[i] = players[i].balance;

        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r2"));

        address champion = tb.champion();
        bool gotPrize;
        for (uint256 i = 0; i < 4; i++) {
            if (players[i] == champion && players[i].balance > before[i]) gotPrize = true;
        }
        assertTrue(gotPrize);
    }

    function test_ChampionEmitsEvent() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));
        vm.warp(block.timestamp + interval);
        vm.recordLogs();
        tb.resolveRoundForTest(keccak256("r2"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == TournamentBracket.ChampionCrowned.selector) found = true;
        }
        assertTrue(found);
    }

    function test_PrizePoolDepletedAfterComplete() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r2"));
        assertEq(tb.prizePool(), 0);
    }

    function test_ProtocolFeeAccruedAfterComplete() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r2"));
        assertGt(tb.protocolFeeBalance(), 0);
    }

    // ── admin ─────────────────────────────────────────────────────────────────

    function test_WithdrawProtocolFees() public {
        _registerAll();
        tb.startTournament();
        tb.seedBracketForTest(keccak256("seed"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r1"));
        vm.warp(block.timestamp + interval);
        tb.resolveRoundForTest(keccak256("r2"));
        uint256 fees = tb.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xFEED);
        tb.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
    }

    function test_SetRoundInterval() public {
        tb.setRoundInterval(2 hours);
        assertEq(tb.roundInterval(), 2 hours);
    }

    function test_SetRoundIntervalZeroReverts() public {
        vm.expectRevert("TournamentBracket: interval=0");
        tb.setRoundInterval(0);
    }

    receive() external payable {}
}
