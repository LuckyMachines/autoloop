// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/MatchmakingEngine.sol";

contract MatchmakingEngineHarness is MatchmakingEngine {
    constructor(uint256 _interval) MatchmakingEngine(_interval) {}

    function tickForTest(bytes32 randomness) external {
        require(pool.length >= 2, "MatchmakingEngine: not enough players");
        require((block.timestamp - lastMatch) >= matchInterval, "MatchmakingEngine: too soon");
        lastMatch = block.timestamp;
        ++_loopID;
        _runMatches(randomness);
    }
}

contract MatchmakingEngineTest is Test {
    MatchmakingEngineHarness public mm;
    uint256 public interval = 1 hours;

    address public alice = address(0xA1);
    address public bob = address(0xB2);
    address public carol = address(0xC3);
    address public dave = address(0xD4);

    function setUp() public {
        mm = new MatchmakingEngineHarness(interval);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("MatchmakingEngine: interval=0");
        new MatchmakingEngineHarness(0);
    }

    function test_InitialState() public view {
        assertEq(mm.matchInterval(), interval);
        assertEq(mm.matchCount(), 0);
        assertEq(mm.poolSize(), 0);
    }

    // ── register ──────────────────────────────────────────────────────────────

    function test_Register() public {
        vm.prank(alice);
        mm.register();
        assertEq(mm.poolSize(), 1);
        assertTrue(mm.registered(alice));
    }

    function test_RegisterEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit MatchmakingEngine.PlayerRegistered(alice);
        mm.register();
    }

    function test_RegisterDuplicateReverts() public {
        vm.prank(alice);
        mm.register();
        vm.prank(alice);
        vm.expectRevert("MatchmakingEngine: already registered");
        mm.register();
    }

    function test_RegisterMultiplePlayers() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.prank(carol);
        mm.register();
        assertEq(mm.poolSize(), 3);
    }

    // ── deregister ────────────────────────────────────────────────────────────

    function test_Deregister() public {
        vm.prank(alice);
        mm.register();
        vm.prank(alice);
        mm.deregister();
        assertEq(mm.poolSize(), 0);
        assertFalse(mm.registered(alice));
    }

    function test_DeregisterEmitsEvent() public {
        vm.prank(alice);
        mm.register();
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit MatchmakingEngine.PlayerDeregistered(alice);
        mm.deregister();
    }

    function test_DeregisterNotRegisteredReverts() public {
        vm.prank(alice);
        vm.expectRevert("MatchmakingEngine: not registered");
        mm.deregister();
    }

    function test_DeregisterMidPoolPreservesOthers() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.prank(carol);
        mm.register();
        vm.prank(bob);
        mm.deregister();
        assertEq(mm.poolSize(), 2);
        assertFalse(mm.registered(bob));
        assertTrue(mm.registered(alice));
        assertTrue(mm.registered(carol));
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyTooFewPlayers() public {
        vm.prank(alice);
        mm.register();
        vm.warp(block.timestamp + interval);
        (bool ready,) = mm.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_NotReadyBeforeInterval() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        (bool ready,) = mm.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyTwoPlayersAfterInterval() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.warp(block.timestamp + interval);
        (bool ready,) = mm.shouldProgressLoop();
        assertTrue(ready);
    }

    // ── tickForTest ───────────────────────────────────────────────────────────

    function test_TickCreatesMatch() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256("seed1"));
        assertEq(mm.matchCount(), 1);
    }

    function test_TickEmitsMatchMade() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.warp(block.timestamp + interval);
        // We can't predict which way the shuffle goes — just verify event fires
        vm.recordLogs();
        mm.tickForTest(keccak256("seed1"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == MatchmakingEngine.MatchMade.selector) {
                found = true;
            }
        }
        assertTrue(found, "MatchMade event not emitted");
    }

    function test_TickUpdatesLastMatch() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        uint256 ts = block.timestamp + interval;
        vm.warp(ts);
        mm.tickForTest(keccak256("seed1"));
        assertEq(mm.lastMatch(), ts);
    }

    function test_FourPlayersProducesTwoMatches() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.prank(carol);
        mm.register();
        vm.prank(dave);
        mm.register();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256("seed1"));
        assertEq(mm.matchCount(), 2);
    }

    function test_ThreePlayersProducesOneMatch() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.prank(carol);
        mm.register();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256("seed1"));
        assertEq(mm.matchCount(), 1); // odd player out — pairs of 2
    }

    function test_MatchPlayersAreFromPool() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256("seed1"));
        (, address p1, address p2,,) = mm.matches(0);
        assertTrue((p1 == alice && p2 == bob) || (p1 == bob && p2 == alice));
    }

    function test_TooSoonReverts() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.expectRevert("MatchmakingEngine: too soon");
        mm.tickForTest(keccak256("seed1"));
    }

    function test_NotEnoughPlayersReverts() public {
        vm.prank(alice);
        mm.register();
        vm.warp(block.timestamp + interval);
        vm.expectRevert("MatchmakingEngine: not enough players");
        mm.tickForTest(keccak256("seed1"));
    }

    function test_MultipleTicksWork() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256("a"));
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256("b"));
        assertEq(mm.matchCount(), 2);
    }

    // ── setMatchInterval ─────────────────────────────────────────────────────

    function test_SetMatchInterval() public {
        mm.setMatchInterval(2 hours);
        assertEq(mm.matchInterval(), 2 hours);
    }

    function test_SetMatchIntervalZeroReverts() public {
        vm.expectRevert("MatchmakingEngine: interval=0");
        mm.setMatchInterval(0);
    }

    function test_SetMatchIntervalOnlyAdmin() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        mm.setMatchInterval(999);
    }

    // ── determinism / shuffle ─────────────────────────────────────────────────

    function test_SameSeedProducesSameMatch() public {
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(bytes32(uint256(42)));
        (, address p1a,,,) = mm.matches(0);

        // Re-deploy and replay
        MatchmakingEngineHarness mm2 = new MatchmakingEngineHarness(interval);
        vm.prank(alice);
        mm2.register();
        vm.prank(bob);
        mm2.register();
        vm.warp(block.timestamp + interval);
        mm2.tickForTest(bytes32(uint256(42)));
        (, address p1b,,,) = mm2.matches(0);

        assertEq(p1a, p1b);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_MatchCountEqualsHalfPoolSize(uint8 extraPlayers) public {
        vm.assume(extraPlayers <= 14); // keep pool size reasonable (2 + extra)
        vm.prank(alice);
        mm.register();
        vm.prank(bob);
        mm.register();
        for (uint256 i = 0; i < extraPlayers; i++) {
            // The test loop bounds make this value far smaller than uint160 max.
            // forge-lint: disable-next-line(unsafe-typecast)
            address p = address(uint160(0x1000 + i));
            vm.prank(p);
            mm.register();
        }
        uint256 poolBefore = mm.poolSize();
        vm.warp(block.timestamp + interval);
        mm.tickForTest(keccak256(abi.encode(extraPlayers)));
        assertEq(mm.matchCount(), poolBefore / 2);
    }
}
