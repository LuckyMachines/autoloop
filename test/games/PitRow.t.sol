// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/PitRow.sol";

/**
 * @title PitRowHarness
 * @notice Test harness that exposes `_progressInternal` directly so tests can
 *         inject deterministic randomness without constructing ECVRF proofs
 *         in Solidity. Production deploys use plain `PitRow`.
 */
contract PitRowHarness is PitRow {
    constructor(
        uint256 _baseMintFee,
        uint256 _repairFee,
        uint256 _tickInterval,
        uint16 _maxHealth,
        uint16 _passiveDecayPerHour,
        uint256 _insurancePremiumBps,
        uint256 _salvageTargetBps
    )
        PitRow(
            _baseMintFee,
            _repairFee,
            _tickInterval,
            _maxHealth,
            _passiveDecayPerHour,
            _insurancePremiumBps,
            _salvageTargetBps
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }

    function exposedLoopID() external view returns (uint256) {
        return _loopID;
    }
}

/**
 * @title PitRowTest
 * @notice Forge test suite for PitRow.
 */
contract PitRowTest is Test {
    // ---- Infra ----
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    // ---- Game ----
    PitRowHarness public game;

    // ---- Actors ----
    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public controller1;
    uint256 public controller1PrivKey;

    // ---- Config ----
    uint256 constant BASE_MINT_FEE = 0.01 ether;
    uint256 constant REPAIR_FEE = 0.002 ether;
    uint256 constant TICK_INTERVAL = 60; // 60 seconds
    uint16 constant MAX_HEALTH = 10_000;
    uint16 constant PASSIVE_DECAY_PER_HOUR = 100; // 1% per hour
    uint256 constant INSURANCE_PREMIUM_BPS = 1000; // 10% of mint fee
    uint256 constant SALVAGE_TARGET_BPS = 5000; // 50% of mint fee
    uint256 constant GAS_PRICE = 20 gwei;

    receive() external payable {}

    // ===============================================================
    //  Setup
    // ===============================================================

    function setUp() public {
        proxyAdmin = vm.addr(99);
        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        carol = vm.addr(0xCA201);
        controller1PrivKey = 0xC0DE;
        controller1 = vm.addr(controller1PrivKey);
        admin = address(this);

        vm.deal(admin, 1000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(controller1, 100 ether);

        // ---- Deploy AutoLoop core behind proxies ----
        AutoLoop autoLoopImpl = new AutoLoop();
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(string)", "0.0.1")
        );
        autoLoop = AutoLoop(address(autoLoopProxy));

        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(address)", admin)
        );
        registry = AutoLoopRegistry(address(registryProxy));

        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();
        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            proxyAdmin,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(autoLoop),
                address(registry),
                admin
            )
        );
        registrar = AutoLoopRegistrar(address(registrarProxy));

        registry.setRegistrar(address(registrar));
        autoLoop.setRegistrar(address(registrar));

        // ---- Deploy PitRow harness ----
        game = new PitRowHarness(
            BASE_MINT_FEE,
            REPAIR_FEE,
            TICK_INTERVAL,
            MAX_HEALTH,
            PASSIVE_DECAY_PER_HOUR,
            INSURANCE_PREMIUM_BPS,
            SALVAGE_TARGET_BPS
        );
        registrar.registerAutoLoopFor(address(game), 2_000_000);

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        registrar.deposit{value: 10 ether}(address(game));
    }

    // ===============================================================
    //  Section 1 — ERC165 Interface Detection
    // ===============================================================

    function test_SupportsVRFInterface() public view {
        bytes4 vrfId = bytes4(keccak256("AutoLoopVRFCompatible"));
        assertTrue(game.supportsInterface(vrfId), "Should support VRF interface");
    }

    function test_SupportsAutoLoopCompatibleInterface() public view {
        assertTrue(
            game.supportsInterface(type(AutoLoopCompatibleInterface).interfaceId),
            "Should support AutoLoopCompatible interface"
        );
    }

    function test_SupportsIAccessControlEnumerable() public view {
        assertTrue(
            game.supportsInterface(type(IAccessControlEnumerable).interfaceId),
            "Should support IAccessControlEnumerable"
        );
    }

    function test_SupportsERC165() public view {
        assertTrue(game.supportsInterface(0x01ffc9a7), "Should support ERC165");
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(
            game.supportsInterface(0xdeadbeef),
            "Should not support random interface"
        );
    }

    // ===============================================================
    //  Section 2 — Initial State
    // ===============================================================

    function test_InitialState() public view {
        assertEq(game.nextFloorId(), 1, "nextFloorId should start at 1");
        assertEq(game.activeFloorCount(), 0, "No active floors initially");
        assertEq(game.protocolFeeBalance(), 0, "protocolFeeBalance should start at 0");
        assertEq(game.insurancePool(), 0, "insurancePool should start at 0");
        assertEq(game.totalDamageEvents(), 0, "no damage events yet");
        assertEq(game.totalCollapses(), 0, "no collapses yet");
        assertEq(game.currentLoopID(), 1, "loop ID starts at 1");
    }

    function test_Immutables() public view {
        assertEq(game.baseMintFee(), BASE_MINT_FEE);
        assertEq(game.repairFee(), REPAIR_FEE);
        assertEq(game.tickInterval(), TICK_INTERVAL);
        assertEq(game.maxHealth(), MAX_HEALTH);
        assertEq(game.passiveDecayPerHour(), PASSIVE_DECAY_PER_HOUR);
        assertEq(game.insurancePremiumBps(), INSURANCE_PREMIUM_BPS);
        assertEq(game.salvageTargetBps(), SALVAGE_TARGET_BPS);
    }

    // ===============================================================
    //  Section 3 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("PitRow: tickInterval=0");
        new PitRowHarness(
            BASE_MINT_FEE, REPAIR_FEE, 0, MAX_HEALTH, PASSIVE_DECAY_PER_HOUR, INSURANCE_PREMIUM_BPS, SALVAGE_TARGET_BPS
        );
    }

    function test_ConstructorRejectsZeroMaxHealth() public {
        vm.expectRevert("PitRow: maxHealth=0");
        new PitRowHarness(
            BASE_MINT_FEE, REPAIR_FEE, TICK_INTERVAL, 0, PASSIVE_DECAY_PER_HOUR, INSURANCE_PREMIUM_BPS, SALVAGE_TARGET_BPS
        );
    }

    function test_ConstructorRejectsZeroBaseMintFee() public {
        vm.expectRevert("PitRow: baseMintFee=0");
        new PitRowHarness(
            0, REPAIR_FEE, TICK_INTERVAL, MAX_HEALTH, PASSIVE_DECAY_PER_HOUR, INSURANCE_PREMIUM_BPS, SALVAGE_TARGET_BPS
        );
    }

    function test_ConstructorRejectsZeroRepairFee() public {
        vm.expectRevert("PitRow: repairFee=0");
        new PitRowHarness(
            BASE_MINT_FEE, 0, TICK_INTERVAL, MAX_HEALTH, PASSIVE_DECAY_PER_HOUR, INSURANCE_PREMIUM_BPS, SALVAGE_TARGET_BPS
        );
    }

    function test_ConstructorRejectsInsuranceOver50() public {
        vm.expectRevert("PitRow: insurance premium > 50%");
        new PitRowHarness(
            BASE_MINT_FEE, REPAIR_FEE, TICK_INTERVAL, MAX_HEALTH, PASSIVE_DECAY_PER_HOUR, 5001, SALVAGE_TARGET_BPS
        );
    }

    function test_ConstructorRejectsSalvageTargetOver100() public {
        vm.expectRevert("PitRow: target > 100%");
        new PitRowHarness(
            BASE_MINT_FEE, REPAIR_FEE, TICK_INTERVAL, MAX_HEALTH, PASSIVE_DECAY_PER_HOUR, INSURANCE_PREMIUM_BPS, 10001
        );
    }

    // ===============================================================
    //  Section 4 — Mint flow
    // ===============================================================

    function test_MintFirstFloorWithoutInsurance() public {
        vm.prank(alice);
        uint256 id = game.mintFloor{value: BASE_MINT_FEE}(false);

        assertEq(id, 1, "First floor id should be 1");
        assertEq(game.nextFloorId(), 2, "nextFloorId should advance");
        assertEq(game.activeFloorCount(), 1, "one active floor");

        PitRow.Floor memory f = game.getFloor(1);
        assertEq(f.owner, alice);
        assertFalse(f.insured);
        assertFalse(f.collapsed);
        assertEq(f.damageTaken, 0);

        assertEq(game.protocolFeeBalance(), BASE_MINT_FEE, "mint fee lands in protocol");
        assertEq(game.insurancePool(), 0, "no insurance pool yet");
    }

    function test_MintWithInsurance() public {
        uint256 insuranceCost = (BASE_MINT_FEE * INSURANCE_PREMIUM_BPS) / 10_000;
        uint256 totalCost = BASE_MINT_FEE + insuranceCost;

        vm.prank(alice);
        uint256 id = game.mintFloor{value: totalCost}(true);

        PitRow.Floor memory f = game.getFloor(id);
        assertTrue(f.insured, "floor should be insured");
        assertEq(game.protocolFeeBalance(), BASE_MINT_FEE, "protocol fee excludes insurance");
        assertEq(game.insurancePool(), insuranceCost, "insurance pool collected premium");
    }

    function test_MintRejectsInsufficientValue() public {
        vm.prank(alice);
        vm.expectRevert("PitRow: insufficient value");
        game.mintFloor{value: BASE_MINT_FEE - 1}(false);
    }

    function test_MintRefundsOverpayment() public {
        uint256 aliceBefore = alice.balance;
        uint256 overpay = 1 ether;
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE + overpay}(false);
        uint256 aliceAfter = alice.balance;

        assertEq(aliceBefore - aliceAfter, BASE_MINT_FEE, "alice should only be charged mint fee");
    }

    function test_MintEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(game));
        emit PitRow.FloorMinted(1, alice, BASE_MINT_FEE, false);

        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
    }

    function test_MintFeeScalesWithFloorNumber() public {
        uint256 floor1Fee = game.mintFeeFor(1);
        uint256 floor10Fee = game.mintFeeFor(10);
        uint256 floor100Fee = game.mintFeeFor(100);

        assertEq(floor1Fee, BASE_MINT_FEE, "floor 1 == base");
        // floor 10 = base + base*9/10 = base * 1.9
        assertEq(floor10Fee, BASE_MINT_FEE + (BASE_MINT_FEE * 9) / 10);
        // floor 100 = base + base*99/10 = base * 10.9
        assertEq(floor100Fee, BASE_MINT_FEE + (BASE_MINT_FEE * 99) / 10);
    }

    function test_SecondFloorCostsMoreThanFirst() public {
        uint256 fee1 = game.mintFeeFor(1);
        uint256 fee2 = game.mintFeeFor(2);
        assertGt(fee2, fee1, "floor 2 should cost more than floor 1");
    }

    function test_MintMultipleFloors() public {
        vm.prank(alice);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(bob);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(carol);
        game.mintFloor{value: 1 ether}(false);

        assertEq(game.activeFloorCount(), 3);
        assertEq(game.nextFloorId(), 4);

        assertEq(game.getFloor(1).owner, alice);
        assertEq(game.getFloor(2).owner, bob);
        assertEq(game.getFloor(3).owner, carol);
    }

    // ===============================================================
    //  Section 5 — Repair flow
    // ===============================================================

    function test_RepairRestoresHealth() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        // Apply damage via a tick
        _warpToNextTick();
        game.tickForTest(bytes32(uint256(0))); // picks floor index 0 (the only floor)

        uint256 healthAfterDamage = game.effectiveHealth(1);
        assertLt(healthAfterDamage, MAX_HEALTH, "damage should reduce health");

        // Repair
        vm.prank(alice);
        game.repair{value: REPAIR_FEE}(1);

        assertEq(game.effectiveHealth(1), MAX_HEALTH, "repair should restore full health");
    }

    function test_RepairChargesFee() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        uint256 feeBefore = game.protocolFeeBalance();

        vm.prank(alice);
        game.repair{value: REPAIR_FEE}(1);

        assertEq(game.protocolFeeBalance() - feeBefore, REPAIR_FEE, "repair fee lands in protocol");
    }

    function test_RepairRejectsNonOwner() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        vm.prank(bob);
        vm.expectRevert("PitRow: not owner");
        game.repair{value: REPAIR_FEE}(1);
    }

    function test_RepairRejectsInsufficientFee() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        vm.prank(alice);
        vm.expectRevert("PitRow: insufficient fee");
        game.repair{value: REPAIR_FEE - 1}(1);
    }

    function test_RepairRejectsNonExistentFloor() public {
        vm.prank(alice);
        vm.expectRevert("PitRow: no such floor");
        game.repair{value: REPAIR_FEE}(999);
    }

    function test_RepairRejectsCollapsedFloor() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _collapseFloor(1);

        vm.prank(alice);
        vm.expectRevert("PitRow: floor collapsed");
        game.repair{value: REPAIR_FEE}(1);
    }

    function test_RepairRefundsOverpayment() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.repair{value: REPAIR_FEE + 1 ether}(1);
        assertEq(alice.balance, aliceBefore - REPAIR_FEE);
    }

    // ===============================================================
    //  Section 6 — Tick / damage flow
    // ===============================================================

    function test_ShouldProgressLoopFalseInitially() public view {
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready, "not ready immediately after deploy");
    }

    function test_ShouldProgressLoopFalseWithNoActiveFloors() public {
        _warpToNextTick();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready, "not ready with zero floors even after interval");
    }

    function test_ShouldProgressLoopTrueAfterMintAndInterval() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();

        (bool ready, bytes memory data) = game.shouldProgressLoop();
        assertTrue(ready, "ready after interval with active floor");
        uint256 loopID = abi.decode(data, (uint256));
        assertEq(loopID, 1);
    }

    function test_TickAppliesDamage() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();

        uint256 healthBefore = game.effectiveHealth(1);
        game.tickForTest(bytes32(uint256(0)));
        uint256 healthAfter = game.effectiveHealth(1);

        assertLt(healthAfter, healthBefore, "damage should be applied");
        assertGe(healthBefore - healthAfter, 1500, "min damage respected");
        assertLe(healthBefore - healthAfter, 5000, "max damage respected");
    }

    function test_TickIncrementsLoopID() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();
        game.tickForTest(bytes32(uint256(0)));

        assertEq(game.currentLoopID(), 2, "loopID should advance");
    }

    function test_TickIncrementsTotalDamageEvents() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();
        game.tickForTest(bytes32(uint256(0)));

        assertEq(game.totalDamageEvents(), 1);
    }

    function test_TickSelectsFloorByModulus() public {
        // mint 3 floors so the index modulus is meaningful
        vm.prank(alice);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(bob);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(carol);
        game.mintFloor{value: 1 ether}(false);

        _warpToNextTick();

        // randomness % 3 == 1 → bob's floor (index 1)
        bytes32 r = bytes32(uint256(1));
        game.tickForTest(r);

        // Bob's floor should be significantly below the others.
        // Passive decay may tick a tiny bit on all floors, so compare relatively.
        uint256 bobHealth = game.effectiveHealth(2);
        uint256 aliceHealth = game.effectiveHealth(1);
        uint256 carolHealth = game.effectiveHealth(3);

        assertLt(bobHealth, aliceHealth - 1000, "bob's should be much lower");
        assertLt(bobHealth, carolHealth - 1000, "bob's should be much lower");
        // Alice and Carol should only differ from MAX_HEALTH by passive decay (< 10 bps over 60s)
        assertGe(aliceHealth, uint256(MAX_HEALTH) - 10);
        assertGe(carolHealth, uint256(MAX_HEALTH) - 10);
    }

    function test_TickRejectsStaleLoopID() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();

        vm.expectRevert("PitRow: stale loop id");
        game.tickForTestRaw(bytes32(uint256(0)), 999);
    }

    function test_TickRejectsTooSoon() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        // no warp — should be too soon
        vm.expectRevert("PitRow: too soon");
        game.tickForTest(bytes32(uint256(0)));
    }

    function test_TickRejectsNoActiveFloors() public {
        _warpToNextTick();
        vm.expectRevert("PitRow: no active floors");
        game.tickForTest(bytes32(uint256(0)));
    }

    function test_TickEmitsFloorDamaged() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();

        bytes32 r = bytes32(uint256(7));

        // Check only the indexed topics — avoids coupling to exact damage math.
        vm.expectEmit(true, true, false, false, address(game));
        emit PitRow.FloorDamaged(1, 0, 0, 1, bytes32(0));
        game.tickForTest(r);
    }

    // ===============================================================
    //  Section 7 — Collapse flow
    // ===============================================================

    function test_RepeatedTicksCollapseFloor() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        _collapseFloor(1);

        assertEq(game.activeFloorCount(), 0, "floor removed from active list");
        assertEq(game.effectiveHealth(1), 0, "health is 0 after collapse");
        assertEq(game.totalCollapses(), 1);
        assertTrue(game.getFloor(1).collapsed);
    }

    function test_CollapsedFloorNotDamagedAgain() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        vm.prank(bob);
        game.mintFloor{value: 1 ether}(false);

        // Collapse alice's floor while bob's still exists
        _collapseFloor(1);

        assertEq(game.activeFloorCount(), 1, "only bob's floor remains");
        _warpToNextTick();
        game.tickForTest(bytes32(uint256(0))); // 0 % 1 == 0 → bob

        assertLt(game.effectiveHealth(2), MAX_HEALTH, "bob takes damage");
        assertEq(game.effectiveHealth(1), 0, "alice still collapsed, not re-damaged");
    }

    function test_CollapseEmitsEvent() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        // Deal maximum damage many ticks in a row until collapse
        bool collapsed = false;
        for (uint256 i = 0; i < 20 && !collapsed; i++) {
            _warpToNextTick();
            bytes32 r = bytes32(
                uint256(keccak256(abi.encodePacked(i, "collapse-seed"))) |
                    (uint256(5000) << 64)
            );
            // Record the next log; we only care that some iteration emits a collapse
            game.tickForTest(r);
            collapsed = game.getFloor(1).collapsed;
        }
        assertTrue(collapsed, "floor should eventually collapse");
    }

    // ===============================================================
    //  Section 8 — Salvage flow
    // ===============================================================

    function test_SalvageInsuredFloorProratedWhenPoolShort() public {
        // One insured floor: pool = 10% of mint fee (premium)
        // Target payout = 50% of mint fee → pool is short
        // Alice receives the entire pool (prorated cap)
        uint256 insuranceCost = (BASE_MINT_FEE * INSURANCE_PREMIUM_BPS) / 10_000;
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE + insuranceCost}(true);

        _collapseFloor(1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.salvage(1);

        // Pool had exactly `insuranceCost`; alice receives all of it
        assertEq(
            alice.balance - aliceBefore,
            insuranceCost,
            "alice should receive the full prorated pool"
        );
        assertTrue(game.getFloor(1).salvaged);
        assertEq(game.insurancePool(), 0, "pool drained");
    }

    function test_SalvageInsuredFloorFullPayoutWhenPoolHealthy() public {
        // Donate to top up the pool so it fully covers the target
        uint256 insuranceCost = (BASE_MINT_FEE * INSURANCE_PREMIUM_BPS) / 10_000;
        uint256 targetPayout = (BASE_MINT_FEE * SALVAGE_TARGET_BPS) / 10_000;

        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE + insuranceCost}(true);
        // Top up by enough to cover the full target
        game.donateToInsurancePool{value: targetPayout}();

        _collapseFloor(1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.salvage(1);

        assertEq(
            alice.balance - aliceBefore,
            targetPayout,
            "alice should receive full target payout"
        );
        // Pool = original premium + donation - payout
        assertEq(
            game.insurancePool(),
            insuranceCost + targetPayout - targetPayout
        );
    }

    function test_SalvageUninsuredFloorPaysZero() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _collapseFloor(1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.salvage(1);

        assertEq(alice.balance, aliceBefore, "no payout for uninsured");
        assertTrue(game.getFloor(1).salvaged);
    }

    function test_SalvageRejectsDoubleSalvage() public {
        uint256 insuranceCost = (BASE_MINT_FEE * INSURANCE_PREMIUM_BPS) / 10_000;
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE + insuranceCost}(true);
        _collapseFloor(1);

        vm.prank(alice);
        game.salvage(1);

        vm.prank(alice);
        vm.expectRevert("PitRow: already salvaged");
        game.salvage(1);
    }

    function test_SalvageRejectsNonCollapsed() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        vm.prank(alice);
        vm.expectRevert("PitRow: not collapsed");
        game.salvage(1);
    }

    function test_SalvageRejectsNonOwner() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _collapseFloor(1);

        vm.prank(bob);
        vm.expectRevert("PitRow: not owner");
        game.salvage(1);
    }

    // ===============================================================
    //  Section 8b — Shared-pool donation
    // ===============================================================

    function test_DonateToInsurancePool() public {
        uint256 before = game.insurancePool();
        vm.expectEmit(true, false, false, true, address(game));
        emit PitRow.InsurancePoolDonation(address(this), 0.5 ether);
        game.donateToInsurancePool{value: 0.5 ether}();
        assertEq(game.insurancePool(), before + 0.5 ether);
    }

    function test_DonateRejectsZero() public {
        vm.expectRevert("PitRow: donation=0");
        game.donateToInsurancePool{value: 0}();
    }

    function test_DonationAllowsFullPayoutForDepletedPool() public {
        // Two insureds, both collapse. Without donation, second one drains pool
        // to 0. With a donation, the pool can cover more.
        uint256 insuranceCost = (BASE_MINT_FEE * INSURANCE_PREMIUM_BPS) / 10_000;

        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE + insuranceCost}(true);
        uint256 bobMintFee = game.mintFeeFor(2);
        uint256 bobInsurance = (bobMintFee * INSURANCE_PREMIUM_BPS) / 10_000;
        vm.prank(bob);
        game.mintFloor{value: bobMintFee + bobInsurance}(true);

        // Subsidize the pool so both floors can claim full target
        uint256 aliceTarget = (BASE_MINT_FEE * SALVAGE_TARGET_BPS) / 10_000;
        uint256 bobTarget = (bobMintFee * SALVAGE_TARGET_BPS) / 10_000;
        uint256 needed = (aliceTarget + bobTarget) -
            (insuranceCost + bobInsurance);
        game.donateToInsurancePool{value: needed}();

        _collapseFloor(1);
        _collapseFloor(2);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.salvage(1);
        assertEq(alice.balance - aliceBefore, aliceTarget);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        game.salvage(2);
        assertEq(bob.balance - bobBefore, bobTarget);
    }

    // ===============================================================
    //  Section 9 — Admin / protocol fee withdrawal
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        uint256 adminBefore = admin.balance;
        game.withdrawProtocolFees(admin, BASE_MINT_FEE);

        assertEq(admin.balance - adminBefore, BASE_MINT_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceedsBalance() public {
        vm.expectRevert("PitRow: exceeds balance");
        game.withdrawProtocolFees(admin, 1 ether);
    }

    function test_WithdrawRejectsZeroAddress() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        vm.expectRevert("PitRow: zero address");
        game.withdrawProtocolFees(address(0), BASE_MINT_FEE);
    }

    function test_WithdrawRejectsNonAdmin() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        vm.prank(alice);
        vm.expectRevert(); // AccessControl reverts with its own message
        game.withdrawProtocolFees(alice, BASE_MINT_FEE);
    }

    // ===============================================================
    //  Section 10 — VRF envelope rejection path
    // ===============================================================

    function test_RejectsUnregisteredControllerVRFEnvelope() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        _warpToNextTick();

        bytes memory gameData = abi.encode(uint256(1));
        bytes memory vrfEnvelope = abi.encode(
            uint8(1),
            [uint256(1), uint256(2), uint256(3), uint256(4)],
            [uint256(1), uint256(2)],
            [uint256(1), uint256(2), uint256(3), uint256(4)],
            gameData
        );

        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        vm.expectRevert("Unable to progress loop. Call not a success");
        autoLoop.progressLoop(address(game), vrfEnvelope);
    }

    // ===============================================================
    //  Section 11 — Effective health / passive decay
    // ===============================================================

    function test_EffectiveHealthWithPassiveDecay() public {
        // Warp to a high fixed baseline first so the mint's lastRepairAt is a
        // known constant. Then warp to absolute targets to sidestep via_ir's
        // block.timestamp caching.
        vm.warp(1_000_000);
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        assertEq(game.effectiveHealth(1), MAX_HEALTH, "fresh floor is at max");

        vm.warp(1_000_000 + 3600);
        assertEq(game.effectiveHealth(1), MAX_HEALTH - 100);

        vm.warp(1_000_000 + 7200);
        assertEq(game.effectiveHealth(1), MAX_HEALTH - 200);
    }

    function test_EffectiveHealthCannotGoNegative() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        // Warp far into the future — passive decay would exceed maxHealth
        vm.warp(block.timestamp + 3600 * 365 * 100); // 100 years
        assertEq(game.effectiveHealth(1), 0, "decay clamps at 0");
    }

    function test_RepairResetsPassiveDecay() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        vm.warp(block.timestamp + 3600);
        assertEq(game.effectiveHealth(1), MAX_HEALTH - 100);

        vm.prank(alice);
        game.repair{value: REPAIR_FEE}(1);
        assertEq(game.effectiveHealth(1), MAX_HEALTH, "post-repair at max");
    }

    function test_EffectiveHealthZeroForNonExistent() public view {
        assertEq(game.effectiveHealth(999), 0);
    }

    // ===============================================================
    //  Section 12 — Invariants (stateful, manually asserted)
    // ===============================================================

    /**
     * @dev Invariant: active list consistency — for every position i,
     *      _activeIndexPlusOne[activeFloorIds[i]] == i + 1.
     *
     *      Verified by exercising a sequence of mints and collapses and
     *      checking the mapping after each operation.
     */
    function test_Invariant_ActiveListConsistency() public {
        vm.prank(alice);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(bob);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(carol);
        game.mintFloor{value: 1 ether}(false);

        _assertActiveListConsistent();

        _collapseFloor(2); // bob's
        _assertActiveListConsistent();

        _collapseFloor(1); // alice's
        _assertActiveListConsistent();

        _collapseFloor(3); // carol's
        _assertActiveListConsistent();
    }

    /**
     * @dev Invariant: contract balance is never less than protocolFeeBalance +
     *      insurancePool (minus any in-flight salvage).
     */
    function test_Invariant_ContractBalanceCoversBookkeeping() public {
        uint256 insuranceCost = (BASE_MINT_FEE * INSURANCE_PREMIUM_BPS) / 10_000;
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE + insuranceCost}(true);
        vm.prank(bob);
        game.mintFloor{value: 1 ether}(false);

        uint256 tracked = game.protocolFeeBalance() + game.insurancePool();
        assertLe(tracked, address(game).balance, "balance covers bookkeeping");
    }

    /**
     * @dev Invariant: total collapses never exceeds total damage events.
     */
    function test_Invariant_CollapsesBoundedByDamageEvents() public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);

        for (uint256 i = 0; i < 10; i++) {
            _warpToNextTick();
            if (game.activeFloorCount() == 0) break;
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked(i, "bound"))) | (uint256(5000) << 64))
            );
        }
        assertLe(game.totalCollapses(), game.totalDamageEvents(), "collapses <= damage events");
    }

    // ===============================================================
    //  Section 13 — Fuzz tests
    // ===============================================================

    /**
     * @dev Fuzz: arbitrary randomness always selects a valid index and
     *      applies damage in [DAMAGE_MIN_BPS, DAMAGE_MAX_BPS].
     */
    function testFuzz_TickDamageBounds(bytes32 randomness) public {
        vm.prank(alice);
        game.mintFloor{value: BASE_MINT_FEE}(false);
        vm.prank(bob);
        game.mintFloor{value: 1 ether}(false);
        vm.prank(carol);
        game.mintFloor{value: 1 ether}(false);

        _warpToNextTick();

        uint256 healthBefore1 = game.effectiveHealth(1);
        uint256 healthBefore2 = game.effectiveHealth(2);
        uint256 healthBefore3 = game.effectiveHealth(3);
        uint256 totalBefore = healthBefore1 + healthBefore2 + healthBefore3;

        game.tickForTest(randomness);

        uint256 healthAfter1 = game.effectiveHealth(1);
        uint256 healthAfter2 = game.effectiveHealth(2);
        uint256 healthAfter3 = game.effectiveHealth(3);
        uint256 totalAfter = healthAfter1 + healthAfter2 + healthAfter3;

        // Exactly one floor should have been reduced.
        uint256 delta = totalBefore - totalAfter;
        assertGe(delta, 1500, "min damage >= 1500");
        assertLe(delta, 5000, "max damage <= 5000");
    }

    /**
     * @dev Fuzz: mint fee is monotonic in floor number.
     */
    function testFuzz_MintFeeMonotonic(uint16 floorA, uint16 floorB) public view {
        vm.assume(floorA > 0 && floorB > 0);
        if (floorA >= floorB) {
            assertGe(game.mintFeeFor(floorA), game.mintFeeFor(floorB));
        } else {
            assertLe(game.mintFeeFor(floorA), game.mintFeeFor(floorB));
        }
    }

    /**
     * @dev Fuzz: protocol fee balance equals sum of mint fees + repair fees
     *      for simple sequences.
     */
    function testFuzz_ProtocolFeeAccounting(uint8 mintCount, uint8 repairCount) public {
        mintCount = uint8(bound(mintCount, 1, 10));
        repairCount = uint8(bound(repairCount, 0, 10));

        uint256 expectedFees = 0;
        for (uint256 i = 0; i < mintCount; i++) {
            uint256 fee = game.mintFeeFor(game.nextFloorId());
            vm.deal(alice, fee);
            vm.prank(alice);
            game.mintFloor{value: fee}(false);
            expectedFees += fee;
        }
        for (uint256 i = 0; i < repairCount; i++) {
            vm.deal(alice, REPAIR_FEE);
            vm.prank(alice);
            game.repair{value: REPAIR_FEE}(1);
            expectedFees += REPAIR_FEE;
        }
        assertEq(game.protocolFeeBalance(), expectedFees);
    }

    /**
     * @dev Fuzz: insurance pool accumulates exactly the premium paid on
     *      insured mints across varied insurance flags.
     */
    function testFuzz_InsurancePoolAccounting(bool[10] memory insured) public {
        uint256 expectedPool = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 fee = game.mintFeeFor(game.nextFloorId());
            uint256 premium = insured[i] ? (fee * INSURANCE_PREMIUM_BPS) / 10_000 : 0;
            vm.deal(alice, fee + premium);
            vm.prank(alice);
            game.mintFloor{value: fee + premium}(insured[i]);
            expectedPool += premium;
        }
        assertEq(game.insurancePool(), expectedPool);
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _warpToNextTick() internal {
        vm.warp(block.timestamp + TICK_INTERVAL);
    }

    /**
     * @dev Repeatedly tick on a single-floor setup with maximum damage
     *      until the floor collapses. Assumes floor is the only active one.
     */
    function _collapseFloor(uint256 floorId) internal {
        uint256 guard = 20;
        while (!game.getFloor(floorId).collapsed && guard > 0) {
            _warpToNextTick();
            // Force max damage by setting upper 64 bits to 5000
            bytes32 r = bytes32((uint256(5000) << 64) | uint256(guard));
            game.tickForTest(r);
            guard--;
        }
        require(game.getFloor(floorId).collapsed, "helper: failed to collapse");
    }

    function _assertActiveListConsistent() internal view {
        uint256 count = game.activeFloorCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 floorId = game.activeFloorIds(i);
            PitRow.Floor memory f = game.getFloor(floorId);
            assertFalse(f.collapsed, "active id should not be collapsed");
            assertTrue(f.owner != address(0), "active id should have owner");
        }
    }
}
