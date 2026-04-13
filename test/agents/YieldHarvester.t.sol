// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/YieldHarvester.sol";

contract YieldHarvesterHarness is YieldHarvester {
    constructor(address _vault, uint256 _interval, uint256 _minYield)
        YieldHarvester(_vault, _interval, _minYield) {}

    function tickForTest() external {
        (,bytes memory data) = this.shouldProgressLoop();
        this.progressLoop(data);
    }
}

contract YieldHarvesterTest is Test {
    YieldHarvesterHarness public harvester;
    MockVault public vault;
    uint256 public interval = 1 days;
    uint256 public minYield = 0;

    function setUp() public {
        // Deploy vault first, harvester second, then wire them up
        vault = new MockVault(address(0)); // placeholder
        harvester = new YieldHarvesterHarness(address(vault), interval, minYield);
        // Re-deploy vault with correct harvester address
        vault = new MockVault(address(harvester));
        harvester.setVault(address(vault));
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeInterval() public view {
        (bool ready,) = harvester.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterIntervalWithYield() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.warp(block.timestamp + interval);
        (bool ready,) = harvester.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_NotReadyBelowMinYield() public {
        harvester.setMinYield(1 ether);
        vm.deal(address(vault), 0.5 ether);
        vault.accrueYield{value: 0.5 ether}(0.5 ether);
        vm.warp(block.timestamp + interval);
        (bool ready,) = harvester.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── progressLoop ─────────────────────────────────────────────────────────

    function test_HarvestTransfersYield() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.warp(block.timestamp + interval);
        uint256 before = harvester.totalHarvested();
        harvester.tickForTest();
        assertGt(harvester.totalHarvested(), before);
    }

    function test_HarvestTakesProtocolFee() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.warp(block.timestamp + interval);
        harvester.tickForTest();
        assertGt(harvester.protocolFeeBalance(), 0);
    }

    function test_HarvestIncrementsCount() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.warp(block.timestamp + interval);
        harvester.tickForTest();
        assertEq(harvester.harvestCount(), 1);
    }

    function test_HarvestTooSoonReverts() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.expectRevert("YieldHarvester: too soon");
        harvester.tickForTest();
    }

    function test_HarvestZeroYieldNoOp() public {
        vm.warp(block.timestamp + interval);
        harvester.tickForTest();
        assertEq(harvester.totalHarvested(), 0);
        assertEq(harvester.harvestCount(), 0);
    }

    function test_HarvestEmitsEvent() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.warp(block.timestamp + interval);
        vm.expectEmit(false, false, false, false);
        emit YieldHarvester.Harvested(1, 0, 0, 0);
        harvester.tickForTest();
    }

    // ── stale loop id ─────────────────────────────────────────────────────────

    function test_StaleLoopId() public {
        vm.warp(block.timestamp + interval);
        bytes memory stale = abi.encode(uint256(99), uint256(0));
        vm.expectRevert("YieldHarvester: stale loop id");
        harvester.progressLoop(stale);
    }

    // ── admin ─────────────────────────────────────────────────────────────────

    function test_SetVaultZeroReverts() public {
        vm.expectRevert("YieldHarvester: zero vault");
        harvester.setVault(address(0));
    }

    function test_SetIntervalZeroReverts() public {
        vm.expectRevert("YieldHarvester: interval=0");
        harvester.setHarvestInterval(0);
    }

    function test_WithdrawFees() public {
        vm.deal(address(vault), 1 ether);
        vault.accrueYield{value: 1 ether}(1 ether);
        vm.warp(block.timestamp + interval);
        harvester.tickForTest();
        uint256 fees = harvester.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xAA);
        harvester.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
        assertEq(harvester.protocolFeeBalance(), 0);
    }

    // ── constructor validation ────────────────────────────────────────────────

    function test_ConstructorZeroVaultReverts() public {
        vm.expectRevert("YieldHarvester: zero vault");
        new YieldHarvesterHarness(address(0), interval, 0);
    }

    function test_ConstructorZeroIntervalReverts() public {
        vm.expectRevert("YieldHarvester: interval=0");
        new YieldHarvesterHarness(address(vault), 0, 0);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_FeeCalculation(uint96 yieldAmount) public {
        vm.assume(yieldAmount > 100);
        vm.deal(address(vault), yieldAmount);
        vault.accrueYield{value: yieldAmount}(yieldAmount);
        vm.warp(block.timestamp + interval);
        harvester.tickForTest();
        uint256 expectedFee = (uint256(yieldAmount) * 100) / 10_000;
        assertEq(harvester.protocolFeeBalance(), expectedFee);
        assertEq(harvester.totalHarvested(), yieldAmount - expectedFee);
    }

    function testFuzz_MultipleHarvestsAccumulate(uint8 rounds) public {
        vm.assume(rounds > 0 && rounds <= 10);
        for (uint256 i = 0; i < rounds; i++) {
            vm.deal(address(vault), 1 ether);
            vault.accrueYield{value: 1 ether}(1 ether);
            vm.warp(block.timestamp + interval + 1);
            harvester.tickForTest();
        }
        assertEq(harvester.harvestCount(), rounds);
    }

    receive() external payable {}
}
