// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/SupplyGovernanceModule.sol";

contract SupplyGovernanceHarness is SupplyGovernanceModule {
    constructor(uint256 _interval) SupplyGovernanceModule(_interval) {}

    function tickForTest(uint256 changeIdx) external {
        bytes memory data = abi.encode(_loopID, changeIdx);
        this.progressLoop(data);
    }
}

contract SupplyGovernanceModuleTest is Test {
    SupplyGovernanceHarness public sgm;
    address public admin = address(this);
    uint256 public interval = 1 hours;
    uint256 public delay = 2 days;

    function setUp() public {
        sgm = new SupplyGovernanceHarness(interval);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("SupplyGovernance: interval=0");
        new SupplyGovernanceHarness(0);
    }

    function test_InitialState() public view {
        assertEq(sgm.checkInterval(), interval);
        assertEq(sgm.nextItemTypeId(), 0);
        assertEq(sgm.getChangeQueueLength(), 0);
        assertEq(sgm.getAuditLogLength(), 0);
    }

    // ── createItemType ────────────────────────────────────────────────────────

    function test_CreateItemType() public {
        uint256 id = sgm.createItemType("Gold Sword", 1000);
        assertEq(id, 0);
        (string memory name, uint256 maxSupply, uint256 current, bool frozen) = sgm.itemTypes(0);
        assertEq(name, "Gold Sword");
        assertEq(maxSupply, 1000);
        assertEq(current, 0);
        assertFalse(frozen);
    }

    function test_CreateItemTypeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit SupplyGovernanceModule.ItemTypeCreated(0, "Gold Sword", 1000);
        sgm.createItemType("Gold Sword", 1000);
    }

    function test_CreateItemTypeOnlyAdmin() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        sgm.createItemType("x", 1);
    }

    function test_CreateItemTypeZeroMaxSupplyReverts() public {
        vm.expectRevert("SupplyGovernance: zero maxSupply");
        sgm.createItemType("bad", 0);
    }

    function test_CreateMultipleItemTypes() public {
        sgm.createItemType("Sword", 100);
        sgm.createItemType("Shield", 50);
        assertEq(sgm.nextItemTypeId(), 2);
    }

    // ── queueSupplyChange ─────────────────────────────────────────────────────

    function test_QueueSupplyChange() public {
        sgm.createItemType("Sword", 1000);
        uint256 idx = sgm.queueSupplyChange(0, 500, "initial mint", delay);
        assertEq(idx, 0);
        assertEq(sgm.getChangeQueueLength(), 1);
    }

    function test_QueueSupplyChangeEmitsEvent() public {
        sgm.createItemType("Sword", 1000);
        vm.expectEmit(true, true, false, false);
        emit SupplyGovernanceModule.ChangeQueued(0, 0, 500, 0, "initial mint");
        sgm.queueSupplyChange(0, 500, "initial mint", delay);
    }

    function test_QueueSupplyChangeUnknownItemReverts() public {
        vm.expectRevert("SupplyGovernance: unknown item");
        sgm.queueSupplyChange(99, 100, "x", delay);
    }

    function test_QueueSupplyChangeZeroDeltaReverts() public {
        sgm.createItemType("Sword", 1000);
        vm.expectRevert("SupplyGovernance: zero delta");
        sgm.queueSupplyChange(0, 0, "x", delay);
    }

    function test_QueueSupplyChangeFrozenItemReverts() public {
        sgm.createItemType("Sword", 1000);
        sgm.freezeItem(0);
        vm.expectRevert("SupplyGovernance: item frozen");
        sgm.queueSupplyChange(0, 100, "x", delay);
    }

    function test_QueueSupplyChangeOnlyAdmin() public {
        sgm.createItemType("Sword", 1000);
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        sgm.queueSupplyChange(0, 100, "x", delay);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyNoQueue() public view {
        (bool ready,) = sgm.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_NotReadyBeforeTimelock() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "x", delay);
        vm.warp(block.timestamp + interval);
        (bool ready,) = sgm.shouldProgressLoop();
        assertFalse(ready); // interval passed but timelock hasn't
    }

    function test_ReadyAfterTimelockAndInterval() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "x", delay);
        vm.warp(block.timestamp + delay + interval);
        (bool ready,) = sgm.shouldProgressLoop();
        assertTrue(ready);
    }

    // ── progressLoop ─────────────────────────────────────────────────────────

    function test_ExecutesSupplyIncrease() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "initial mint", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        (,, uint256 current,) = sgm.itemTypes(0);
        assertEq(current, 100);
    }

    function test_ExecutesSupplyDecrease() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 500, "initial mint", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        sgm.queueSupplyChange(0, -200, "burn", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(1);
        (,, uint256 current,) = sgm.itemTypes(0);
        assertEq(current, 300);
    }

    function test_SupplyCapEnforced() public {
        sgm.createItemType("Sword", 100);
        sgm.queueSupplyChange(0, 200, "over cap", delay); // would exceed maxSupply
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        (,, uint256 current,) = sgm.itemTypes(0);
        assertEq(current, 100); // capped at maxSupply
    }

    function test_DecreaseCannotGoBelowZero() public {
        sgm.createItemType("Sword", 1000);
        // currentSupply starts at 0, decrease of 500 should floor at 0
        sgm.queueSupplyChange(0, -500, "burn from empty", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        (,, uint256 current,) = sgm.itemTypes(0);
        assertEq(current, 0);
    }

    function test_ExecuteEmitsEvent() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        vm.warp(block.timestamp + delay + interval);
        vm.expectEmit(true, false, false, false);
        emit SupplyGovernanceModule.SupplyChanged(0, 0, 100, "mint");
        sgm.tickForTest(0);
    }

    function test_AuditLogPopulated() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        assertEq(sgm.getAuditLogLength(), 1);
        SupplyGovernanceModule.ChangeRecord memory r = sgm.getAuditLog(0);
        assertEq(r.oldSupply, 0);
        assertEq(r.newSupply, 100);
    }

    function test_CannotExecuteTwice() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        vm.warp(block.timestamp + interval);
        vm.expectRevert("SupplyGovernance: already executed");
        sgm.tickForTest(0);
    }

    function test_CannotExecuteBeforeTimelock() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay); // delay = 2 days
        // Warp past interval only — check interval passes but timelock hasn't
        vm.warp(block.timestamp + interval);
        vm.expectRevert("SupplyGovernance: timelock active");
        sgm.tickForTest(0);
    }

    function test_StaleLoopIdReverts() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        vm.warp(block.timestamp + delay + interval);
        bytes memory stale = abi.encode(uint256(99), uint256(0));
        vm.expectRevert("SupplyGovernance: stale loop id");
        sgm.progressLoop(stale);
    }

    // ── cancelChange ─────────────────────────────────────────────────────────

    function test_CancelChange() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        sgm.cancelChange(0);
        (,,,, bool executed, bool cancelled) = sgm.changeQueue(0);
        assertTrue(cancelled);
        assertFalse(executed);
    }

    function test_CancelEmitsEvent() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        vm.expectEmit(true, false, false, false);
        emit SupplyGovernanceModule.ChangeCancelled(0);
        sgm.cancelChange(0);
    }

    function test_CancelAlreadyCancelledReverts() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        sgm.cancelChange(0);
        vm.expectRevert("SupplyGovernance: already cancelled");
        sgm.cancelChange(0);
    }

    function test_CannotExecuteCancelledChange() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        sgm.cancelChange(0);
        vm.warp(block.timestamp + delay + interval);
        // No ready change — shouldProgressLoop returns false
        (bool ready,) = sgm.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── freezeItem ────────────────────────────────────────────────────────────

    function test_FreezeItem() public {
        sgm.createItemType("Sword", 1000);
        sgm.freezeItem(0);
        (,,, bool frozen) = sgm.itemTypes(0);
        assertTrue(frozen);
    }

    function test_FreezeEmitsEvent() public {
        sgm.createItemType("Sword", 1000);
        vm.expectEmit(true, false, false, false);
        emit SupplyGovernanceModule.ItemFrozen(0);
        sgm.freezeItem(0);
    }

    function test_FreezeBlocksExecution() public {
        sgm.createItemType("Sword", 1000);
        sgm.queueSupplyChange(0, 100, "mint", delay);
        sgm.freezeItem(0);
        vm.warp(block.timestamp + delay + interval);
        vm.expectRevert("SupplyGovernance: item frozen");
        sgm.tickForTest(0);
    }

    function test_FreezeUnknownItemReverts() public {
        vm.expectRevert("SupplyGovernance: unknown item");
        sgm.freezeItem(99);
    }

    // ── setCheckInterval ──────────────────────────────────────────────────────

    function test_SetCheckInterval() public {
        sgm.setCheckInterval(2 hours);
        assertEq(sgm.checkInterval(), 2 hours);
    }

    function test_SetCheckIntervalZeroReverts() public {
        vm.expectRevert("SupplyGovernance: interval=0");
        sgm.setCheckInterval(0);
    }

    // ── pendingChangeCount ────────────────────────────────────────────────────

    function test_PendingChangeCount() public {
        sgm.createItemType("Sword", 1000);
        assertEq(sgm.pendingChangeCount(), 0);
        sgm.queueSupplyChange(0, 100, "a", delay);
        sgm.queueSupplyChange(0, 200, "b", delay);
        assertEq(sgm.pendingChangeCount(), 2);
        sgm.cancelChange(0);
        assertEq(sgm.pendingChangeCount(), 1);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_SupplyNeverExceedsMax(uint64 maxS, uint64 delta) public {
        vm.assume(maxS > 0 && delta > 0);
        sgm.createItemType("x", maxS);
        sgm.queueSupplyChange(0, int256(uint256(delta)), "mint", delay);
        vm.warp(block.timestamp + delay + interval);
        sgm.tickForTest(0);
        (,, uint256 current,) = sgm.itemTypes(0);
        assertLe(current, maxS);
    }
}
