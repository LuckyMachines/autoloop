// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/ParameterAlerter.sol";

contract ParameterAlerterHarness is ParameterAlerter {
    constructor(uint256 _interval) ParameterAlerter(_interval) {}

    function tickForTest() external {
        bytes memory data = abi.encode(_loopID);
        this.progressLoop(data);
    }
}

contract ParameterAlerterTest is Test {
    ParameterAlerterHarness public pa;
    address public admin = address(this);
    uint256 public interval = 1 hours;

    function setUp() public {
        pa = new ParameterAlerterHarness(interval);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("ParameterAlerter: interval=0");
        new ParameterAlerterHarness(0);
    }

    function test_InitialState() public view {
        assertEq(pa.checkInterval(), interval);
        assertEq(pa.changeCount(), 0);
        assertEq(pa.getParamKeyCount(), 0);
        assertEq(pa.getAuditLogLength(), 0);
    }

    // ── addTrackedParam ───────────────────────────────────────────────────────

    function test_AddTrackedParam() public {
        pa.addTrackedParam("dropRate", 100);
        assertEq(pa.getParamKeyCount(), 1);
        assertEq(pa.currentParams("dropRate"), 100);
        assertEq(pa.lastSnapshotted("dropRate"), 100);
        assertTrue(pa.tracked("dropRate"));
    }

    function test_AddTrackedParamEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ParameterAlerter.ParamAdded("dropRate", 100);
        pa.addTrackedParam("dropRate", 100);
    }

    function test_AddTrackedParamDuplicateReverts() public {
        pa.addTrackedParam("dropRate", 100);
        vm.expectRevert("ParameterAlerter: already tracked");
        pa.addTrackedParam("dropRate", 200);
    }

    function test_AddTrackedParamOnlyAdmin() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        pa.addTrackedParam("x", 1);
    }

    function test_AddMultipleParams() public {
        pa.addTrackedParam("dropRate", 100);
        pa.addTrackedParam("matchTimeout", 300);
        pa.addTrackedParam("lobbySize", 8);
        assertEq(pa.getParamKeyCount(), 3);
    }

    // ── setParam ──────────────────────────────────────────────────────────────

    function test_SetParam() public {
        pa.addTrackedParam("dropRate", 100);
        pa.setParam("dropRate", 50);
        assertEq(pa.currentParams("dropRate"), 50);
        // lastSnapshotted not updated yet — needs a tick
        assertEq(pa.lastSnapshotted("dropRate"), 100);
    }

    function test_SetParamUnknownKeyReverts() public {
        vm.expectRevert("ParameterAlerter: unknown key");
        pa.setParam("unknown", 1);
    }

    function test_SetParamOnlyAdmin() public {
        pa.addTrackedParam("dropRate", 100);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        pa.setParam("dropRate", 50);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeInterval() public view {
        (bool ready,) = pa.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterInterval() public {
        vm.warp(block.timestamp + interval);
        (bool ready,) = pa.shouldProgressLoop();
        assertTrue(ready);
    }

    // ── progressLoop — no changes ─────────────────────────────────────────────

    function test_TickWithNoParams() public {
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 0);
        assertEq(pa.getAuditLogLength(), 0);
    }

    function test_TickWithUnchangedParams() public {
        pa.addTrackedParam("dropRate", 100);
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 0);
        assertEq(pa.getAuditLogLength(), 0);
    }

    // ── progressLoop — change detection ──────────────────────────────────────

    function test_TickDetectsChange() public {
        pa.addTrackedParam("dropRate", 100);
        pa.setParam("dropRate", 50);
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 1);
        assertEq(pa.getAuditLogLength(), 1);
    }

    function test_TickUpdatesLastSnapshotted() public {
        pa.addTrackedParam("dropRate", 100);
        pa.setParam("dropRate", 50);
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.lastSnapshotted("dropRate"), 50);
    }

    function test_TickEmitsParamChangedEvent() public {
        pa.addTrackedParam("dropRate", 100);
        pa.setParam("dropRate", 50);
        vm.warp(block.timestamp + interval);
        vm.expectEmit(false, false, false, false);
        emit ParameterAlerter.ParamChanged("dropRate", 100, 50, block.timestamp + interval);
        pa.tickForTest();
    }

    function test_AuditLogEntry() public {
        pa.addTrackedParam("dropRate", 100);
        pa.setParam("dropRate", 42);
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        ParameterAlerter.ChangeRecord memory r = pa.getAuditLog(0);
        assertEq(r.oldValue, 100);
        assertEq(r.newValue, 42);
    }

    function test_MultipleParamsDetected() public {
        pa.addTrackedParam("dropRate", 100);
        pa.addTrackedParam("timeout", 30);
        pa.setParam("dropRate", 50);
        pa.setParam("timeout", 60);
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 2);
        assertEq(pa.getAuditLogLength(), 2);
    }

    function test_OnlyChangedParamsLogged() public {
        pa.addTrackedParam("dropRate", 100);
        pa.addTrackedParam("timeout", 30);
        pa.setParam("dropRate", 50);
        // timeout unchanged
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 1);
    }

    // ── progressLoop — guards ─────────────────────────────────────────────────

    function test_TickTooSoonReverts() public {
        vm.expectRevert("ParameterAlerter: too soon");
        pa.tickForTest();
    }

    function test_StaleLoopIdReverts() public {
        vm.warp(block.timestamp + interval);
        bytes memory stale = abi.encode(uint256(99));
        vm.expectRevert("ParameterAlerter: stale loop id");
        pa.progressLoop(stale);
    }

    // ── setCheckInterval ──────────────────────────────────────────────────────

    function test_SetCheckInterval() public {
        pa.setCheckInterval(2 hours);
        assertEq(pa.checkInterval(), 2 hours);
    }

    function test_SetCheckIntervalZeroReverts() public {
        vm.expectRevert("ParameterAlerter: interval=0");
        pa.setCheckInterval(0);
    }

    function test_SetCheckIntervalOnlyAdmin() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        pa.setCheckInterval(999);
    }

    // ── loop progression ──────────────────────────────────────────────────────

    function test_LoopIdIncrementsEachTick() public {
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        // loop ran twice, no revert = IDs were correct
        assertEq(pa.getAuditLogLength(), 0); // no changes, just ticks
    }

    function test_ChangePersistsAcrossMultipleTicks() public {
        pa.addTrackedParam("x", 1);
        pa.setParam("x", 2);
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 1);

        // Second tick with no further change
        vm.warp(block.timestamp + interval);
        pa.tickForTest();
        assertEq(pa.changeCount(), 1); // no new changes
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_ChangeCountNeverDecrements(uint8 numChanges) public {
        pa.addTrackedParam("rate", 0);
        uint256 lastCount;
        for (uint256 i = 0; i < numChanges; i++) {
            pa.setParam("rate", i + 1);
            vm.warp(block.timestamp + interval);
            pa.tickForTest();
            assertGe(pa.changeCount(), lastCount);
            lastCount = pa.changeCount();
        }
    }
}
