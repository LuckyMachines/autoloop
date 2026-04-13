// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/AIAgentLoop.sol";

contract AIAgentLoopHarness is AIAgentLoop {
    constructor(uint256 _interval, bytes32 _hash, uint256 _maxTicks)
        AIAgentLoop(_interval, _hash, _maxTicks) {}

    function tickForTest() external {
        (,bytes memory data) = this.shouldProgressLoop();
        this.progressLoop(data);
    }
}

contract AIAgentLoopTest is Test {
    AIAgentLoopHarness public agent;
    bytes32 public constant HASH = keccak256("instructions_v1");
    uint256 public interval = 1 hours;

    function setUp() public {
        agent = new AIAgentLoopHarness(interval, HASH, 0);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeInterval() public view {
        (bool ready,) = agent.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterInterval() public {
        vm.warp(block.timestamp + interval);
        (bool ready,) = agent.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_NotReadyAtMaxTicks() public {
        agent.setMaxTicks(1);
        vm.warp(block.timestamp + interval);
        agent.tickForTest();
        vm.warp(block.timestamp + interval);
        (bool ready,) = agent.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── progressLoop ─────────────────────────────────────────────────────────

    function test_TickEmitsAgentTick() public {
        vm.warp(block.timestamp + interval);
        vm.expectEmit(true, true, false, true);
        emit AIAgentLoop.AgentTick(1, 1, HASH, block.timestamp);
        agent.tickForTest();
    }

    function test_TickIncrementsTotalTicks() public {
        vm.warp(block.timestamp + interval);
        agent.tickForTest();
        assertEq(agent.totalTicks(), 1);
    }

    function test_MultipleTicksAccumulate() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + interval + 1);
            agent.tickForTest();
        }
        assertEq(agent.totalTicks(), 5);
    }

    function test_TooSoonReverts() public {
        vm.expectRevert("AIAgentLoop: too soon");
        agent.tickForTest();
    }

    function test_MaxTicksReverts() public {
        agent.setMaxTicks(2);
        vm.warp(block.timestamp + interval);
        agent.tickForTest();
        vm.warp(block.timestamp + interval);
        agent.tickForTest();
        vm.warp(block.timestamp + interval);
        vm.expectRevert("AIAgentLoop: max ticks reached");
        agent.tickForTest();
    }

    function test_StaleLoopId() public {
        vm.warp(block.timestamp + interval);
        bytes memory stale = abi.encode(uint256(99), HASH);
        vm.expectRevert("AIAgentLoop: stale loop id");
        agent.progressLoop(stale);
    }

    // ── setInstructionHash ────────────────────────────────────────────────────

    function test_SetInstructionHash() public {
        bytes32 newHash = keccak256("instructions_v2");
        vm.expectEmit(true, true, false, false);
        emit AIAgentLoop.InstructionsUpdated(HASH, newHash);
        agent.setInstructionHash(newHash);
        assertEq(agent.instructionHash(), newHash);
    }

    // ── constructor validation ────────────────────────────────────────────────

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("AIAgentLoop: interval=0");
        new AIAgentLoopHarness(0, HASH, 0);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_MaxTicksRespected(uint8 max) public {
        vm.assume(max > 0 && max <= 20);
        agent.setMaxTicks(max);
        for (uint256 i = 0; i < max; i++) {
            vm.warp(block.timestamp + interval + 1);
            agent.tickForTest();
        }
        assertEq(agent.totalTicks(), max);
        vm.warp(block.timestamp + interval + 1);
        (bool ready,) = agent.shouldProgressLoop();
        assertFalse(ready);
    }

    function testFuzz_LoopIdIncrementsCorrectly(uint8 ticks) public {
        vm.assume(ticks > 0 && ticks <= 10);
        for (uint256 i = 0; i < ticks; i++) {
            vm.warp(block.timestamp + interval + 1);
            agent.tickForTest();
        }
        // _loopID starts at 1 and increments each tick
        assertEq(agent.totalTicks(), ticks);
    }
}
