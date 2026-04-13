// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/DAOExecutor.sol";

contract MockTarget {
    uint256 public value;
    function setValue(uint256 v) external { value = v; }
    function revertAlways() external pure { revert("always reverts"); }
}

contract DAOExecutorHarness is DAOExecutor {
    constructor(uint256 _interval) DAOExecutor(_interval) {}

    function tickForTest(uint256 proposalId) external {
        bytes memory data = abi.encode(_loopID, proposalId);
        this.progressLoop(data);
    }
}

contract DAOExecutorTest is Test {
    DAOExecutorHarness public exec;
    MockTarget public target;
    uint256 public interval = 1 hours;

    function setUp() public {
        exec = new DAOExecutorHarness(interval);
        target = new MockTarget();
    }

    function _queueProposal(uint256 etaOffset) internal returns (uint256 id) {
        bytes memory callData = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        id = exec.queueProposal(address(target), callData, block.timestamp + etaOffset, "Set value to 42");
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyNoProposals() public view {
        (bool ready,) = exec.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_NotReadyProposalNotMatured() public {
        _queueProposal(2 days);
        vm.warp(block.timestamp + interval);
        (bool ready,) = exec.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyWhenProposalMatured() public {
        uint256 id = _queueProposal(1 hours);
        vm.warp(block.timestamp + 2 hours);
        (bool ready, bytes memory data) = exec.shouldProgressLoop();
        assertTrue(ready);
        (, uint256 encodedId) = abi.decode(data, (uint256, uint256));
        assertEq(encodedId, id);
    }

    // ── queueProposal ─────────────────────────────────────────────────────────

    function test_QueueProposalEmitsEvent() public {
        bytes memory callData = abi.encodeWithSelector(MockTarget.setValue.selector, 1);
        uint256 eta = block.timestamp + 1 hours;
        vm.expectEmit(true, false, false, false);
        emit DAOExecutor.ProposalQueued(0, address(target), eta, "test");
        exec.queueProposal(address(target), callData, eta, "test");
    }

    function test_QueueProposalZeroTargetReverts() public {
        vm.expectRevert("DAOExecutor: zero target");
        exec.queueProposal(address(0), "", block.timestamp + 1 hours, "bad");
    }

    function test_QueueProposalEtaInPastReverts() public {
        vm.expectRevert("DAOExecutor: eta in past");
        exec.queueProposal(address(target), "", block.timestamp, "bad");
    }

    // ── progressLoop ─────────────────────────────────────────────────────────

    function test_ExecutesProposal() public {
        uint256 id = _queueProposal(1 hours);
        vm.warp(block.timestamp + 2 hours);
        exec.tickForTest(id);
        assertEq(target.value(), 42);
    }

    function test_ExecutionMarksProposalDone() public {
        uint256 id = _queueProposal(1 hours);
        vm.warp(block.timestamp + 2 hours);
        exec.tickForTest(id);
        (,,,,bool executed,,) = exec.proposals(id);
        assertTrue(executed);
    }

    function test_ExecutionIncrementsCount() public {
        uint256 id = _queueProposal(1 hours);
        vm.warp(block.timestamp + 2 hours);
        exec.tickForTest(id);
        assertEq(exec.executedCount(), 1);
    }

    function test_CannotExecuteTwice() public {
        uint256 id = _queueProposal(1 hours);
        vm.warp(block.timestamp + 2 hours);
        exec.tickForTest(id);
        vm.warp(block.timestamp + interval);
        vm.expectRevert("DAOExecutor: already executed");
        exec.tickForTest(id);
    }

    function test_CannotExecuteCancelled() public {
        uint256 id = _queueProposal(1 hours);
        exec.cancelProposal(id);
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert("DAOExecutor: cancelled");
        exec.tickForTest(id);
    }

    function test_CannotExecuteBeforeTimelock() public {
        uint256 id = _queueProposal(2 days);
        vm.warp(block.timestamp + interval);
        vm.expectRevert("DAOExecutor: timelock active");
        exec.tickForTest(id);
    }

    function test_TooSoonReverts() public {
        // First execution succeeds (lastCheck starts at 0, so interval has elapsed)
        uint256 id1 = _queueProposal(interval);
        vm.warp(block.timestamp + interval + 1);
        exec.tickForTest(id1); // succeeds, sets lastCheck = block.timestamp

        // Immediately queue another proposal — eta is already past, but checkInterval has not
        uint256 id2 = _queueProposal(1);
        vm.warp(block.timestamp + 2); // past eta, but only 2s since lastCheck
        vm.expectRevert("DAOExecutor: too soon");
        exec.tickForTest(id2);
    }

    function test_FailingCallEmitsWithSuccessFalse() public {
        bytes memory callData = abi.encodeWithSelector(MockTarget.revertAlways.selector);
        uint256 id = exec.queueProposal(address(target), callData, block.timestamp + 1 hours, "will fail");
        vm.warp(block.timestamp + 2 hours);
        vm.expectEmit(true, false, false, false);
        emit DAOExecutor.ProposalExecuted(id, address(target), false, 0);
        exec.tickForTest(id);
    }

    // ── pendingProposalCount ──────────────────────────────────────────────────

    function test_PendingCount() public {
        _queueProposal(1 hours);
        _queueProposal(2 hours);
        assertEq(exec.pendingProposalCount(), 2);
    }

    function test_PendingCountDecreasesAfterExecution() public {
        uint256 id = _queueProposal(1 hours);
        _queueProposal(2 hours);
        vm.warp(block.timestamp + 2 hours);
        exec.tickForTest(id);
        assertEq(exec.pendingProposalCount(), 1);
    }

    // ── stale loop id ─────────────────────────────────────────────────────────

    function test_StaleLoopId() public {
        uint256 id = _queueProposal(1 hours);
        vm.warp(block.timestamp + 2 hours);
        bytes memory stale = abi.encode(uint256(99), id);
        vm.expectRevert("DAOExecutor: stale loop id");
        exec.progressLoop(stale);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_MultipleProposalsQueue(uint8 count) public {
        vm.assume(count > 0 && count <= 20);
        for (uint256 i = 0; i < count; i++) {
            _queueProposal((i + 1) * 1 hours);
        }
        assertEq(exec.pendingProposalCount(), count);
    }
}
