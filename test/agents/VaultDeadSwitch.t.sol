// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/VaultDeadSwitch.sol";

contract VaultDeadSwitchHarness is VaultDeadSwitch {
    constructor(address _owner, address _beneficiary, uint256 _interval)
        VaultDeadSwitch(_owner, _beneficiary, _interval) {}

    function tickForTest() external {
        bytes memory data = abi.encode(_loopID);
        this.progressLoop(data);
    }
}

contract VaultDeadSwitchTest is Test {
    VaultDeadSwitchHarness public dsw;
    address public owner   = address(0xA1);
    address public beneficiary = address(0xB2);
    address public admin   = address(this);
    uint256 public interval = 30 days;

    function setUp() public {
        dsw = new VaultDeadSwitchHarness(owner, beneficiary, interval);
        dsw.grantRole(dsw.DEFAULT_ADMIN_ROLE(), admin);
        vm.deal(address(dsw), 1 ether);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeInterval() public view {
        (bool ready,) = dsw.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterInterval() public {
        vm.warp(block.timestamp + interval);
        (bool ready,) = dsw.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_NotReadyAfterCheckIn() public {
        vm.warp(block.timestamp + interval);
        vm.prank(owner);
        dsw.checkIn();
        (bool ready,) = dsw.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── checkIn ───────────────────────────────────────────────────────────────

    function test_CheckInResetsTimer() public {
        vm.warp(block.timestamp + interval / 2);
        vm.prank(owner);
        dsw.checkIn();
        assertEq(dsw.lastCheckIn(), block.timestamp);
    }

    function test_CheckInOnlyOwner() public {
        vm.expectRevert("VaultDeadSwitch: not owner");
        dsw.checkIn();
    }

    function test_CheckInEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit VaultDeadSwitch.CheckIn(owner, block.timestamp);
        dsw.checkIn();
    }

    // ── progressLoop (trigger) ────────────────────────────────────────────────

    function test_TriggerTransfersFunds() public {
        vm.warp(block.timestamp + interval);
        uint256 before = beneficiary.balance;
        dsw.tickForTest();
        assertTrue(beneficiary.balance > before);
    }

    function test_TriggerTakesProtocolFee() public {
        vm.warp(block.timestamp + interval);
        dsw.tickForTest();
        assertGt(dsw.protocolFeeBalance(), 0);
    }

    function test_TriggerSetsFlagTrue() public {
        vm.warp(block.timestamp + interval);
        dsw.tickForTest();
        assertTrue(dsw.triggered());
    }

    function test_TriggerEmitsEvent() public {
        vm.warp(block.timestamp + interval);
        vm.expectEmit(true, false, false, false);
        emit VaultDeadSwitch.SwitchTriggered(beneficiary, 0, 0);
        dsw.tickForTest();
    }

    function test_CannotTriggerTwice() public {
        vm.warp(block.timestamp + interval);
        dsw.tickForTest();
        vm.expectRevert("VaultDeadSwitch: already triggered");
        dsw.tickForTest();
    }

    function test_CannotTriggerTooSoon() public {
        vm.expectRevert("VaultDeadSwitch: too soon");
        dsw.tickForTest();
    }

    function test_TriggerWithZeroBalance() public {
        vm.deal(address(dsw), 0);
        vm.warp(block.timestamp + interval);
        dsw.tickForTest();
        assertTrue(dsw.triggered());
    }

    // ── stale loop id ─────────────────────────────────────────────────────────

    function test_StaleLoopId() public {
        vm.warp(block.timestamp + interval);
        bytes memory stale = abi.encode(uint256(99));
        vm.expectRevert("VaultDeadSwitch: stale loop id");
        dsw.progressLoop(stale);
    }

    // ── secondsUntilTrigger ───────────────────────────────────────────────────

    function test_SecondsUntilTriggerDecreases() public {
        uint256 s1 = dsw.secondsUntilTrigger();
        vm.warp(block.timestamp + 1 days);
        uint256 s2 = dsw.secondsUntilTrigger();
        assertLt(s2, s1);
    }

    function test_SecondsUntilTriggerZeroWhenOverdue() public {
        vm.warp(block.timestamp + interval + 1);
        assertEq(dsw.secondsUntilTrigger(), 0);
    }

    // ── setBeneficiary ────────────────────────────────────────────────────────

    function test_SetBeneficiary() public {
        address newBeneficiary = address(0xC3);
        vm.prank(owner);
        dsw.setBeneficiary(newBeneficiary);
        assertEq(dsw.beneficiary(), newBeneficiary);
    }

    function test_SetBeneficiaryOnlyOwner() public {
        vm.expectRevert("VaultDeadSwitch: not owner");
        dsw.setBeneficiary(address(0xC3));
    }

    function test_SetBeneficiaryZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert("VaultDeadSwitch: zero beneficiary");
        dsw.setBeneficiary(address(0));
    }

    // ── transferOwnership ─────────────────────────────────────────────────────

    function test_TransferOwnership() public {
        address newOwner = address(0xD4);
        vm.prank(owner);
        dsw.transferOwnership(newOwner);
        assertEq(dsw.owner(), newOwner);
    }

    function test_TransferOwnershipOnlyOwner() public {
        vm.expectRevert("VaultDeadSwitch: not owner");
        dsw.transferOwnership(address(0xD4));
    }

    // ── withdrawProtocolFees ──────────────────────────────────────────────────

    function test_WithdrawFees() public {
        vm.warp(block.timestamp + interval);
        dsw.tickForTest();
        uint256 fees = dsw.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xE5);
        dsw.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
        assertEq(dsw.protocolFeeBalance(), 0);
    }

    // ── receive ───────────────────────────────────────────────────────────────

    function test_Receive() public {
        uint256 before = address(dsw).balance;
        vm.deal(address(this), 0.5 ether);
        (bool ok,) = address(dsw).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(dsw).balance, before + 0.5 ether);
    }

    // ── constructor validation ────────────────────────────────────────────────

    function test_ConstructorZeroOwnerReverts() public {
        vm.expectRevert("VaultDeadSwitch: zero owner");
        new VaultDeadSwitchHarness(address(0), beneficiary, interval);
    }

    function test_ConstructorZeroBeneficiaryReverts() public {
        vm.expectRevert("VaultDeadSwitch: zero beneficiary");
        new VaultDeadSwitchHarness(owner, address(0), interval);
    }

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("VaultDeadSwitch: interval=0");
        new VaultDeadSwitchHarness(owner, beneficiary, 0);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_TriggerPaysCorrectly(uint96 depositAmount) public {
        vm.assume(depositAmount > 1000);
        vm.deal(address(dsw), depositAmount);
        vm.warp(block.timestamp + interval);
        uint256 before = beneficiary.balance;
        dsw.tickForTest();
        uint256 expectedFee = (uint256(depositAmount) * 200) / 10_000;
        uint256 expectedPayout = depositAmount - expectedFee;
        assertEq(beneficiary.balance - before, expectedPayout);
        assertEq(dsw.protocolFeeBalance(), expectedFee);
    }

    function testFuzz_SecondsUntilTriggerNeverUnderflows(uint32 elapsed) public {
        vm.warp(block.timestamp + elapsed);
        uint256 s = dsw.secondsUntilTrigger();
        assertLe(s, interval);
    }

    receive() external payable {}
}
