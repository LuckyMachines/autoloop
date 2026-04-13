// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/VoidHarvester.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract VoidHarvesterHarness is VoidHarvester {
    constructor(
        uint256 _probeFee,
        uint256 _missionFee,
        uint256 _missionInterval,
        uint256 _protocolRakeBps,
        uint32 _initialIntegrity,
        uint32 _minIntegrity,
        uint256 _maxProbesPerMission
    )
        VoidHarvester(
            _probeFee,
            _missionFee,
            _missionInterval,
            _protocolRakeBps,
            _initialIntegrity,
            _minIntegrity,
            _maxProbesPerMission
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract VoidHarvesterTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    VoidHarvesterHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant PROBE_FEE = 0.01 ether;
    uint256 constant MISSION_FEE = 0.001 ether;
    uint256 constant MISSION_INTERVAL = 60;
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint32 constant INITIAL_INTEGRITY = 500;
    uint32 constant MIN_INTEGRITY = 50;
    uint256 constant MAX_PROBES = 8;
    uint256 constant GAS_PRICE = 20 gwei;

    receive() external payable {}

    function setUp() public {
        proxyAdmin = vm.addr(99);
        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        carol = vm.addr(0xCA20A);
        dave = vm.addr(0xDA5E);
        controller1 = vm.addr(0xC0DE);
        admin = address(this);

        vm.deal(admin, 1000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(dave, 100 ether);
        vm.deal(controller1, 100 ether);

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

        game = new VoidHarvesterHarness(
            PROBE_FEE,
            MISSION_FEE,
            MISSION_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_INTEGRITY,
            MIN_INTEGRITY,
            MAX_PROBES
        );
        registrar.registerAutoLoopFor(address(game), 2_000_000);

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        registrar.deposit{value: 10 ether}(address(game));
    }

    // ===============================================================
    //  Section 1 — ERC165 / initial state
    // ===============================================================

    function test_SupportsVRFInterface() public view {
        assertTrue(
            game.supportsInterface(bytes4(keccak256("AutoLoopVRFCompatible")))
        );
    }

    function test_SupportsAutoLoopInterface() public view {
        assertTrue(
            game.supportsInterface(type(AutoLoopCompatibleInterface).interfaceId)
        );
    }

    function test_InitialState() public view {
        assertEq(game.nextProbeId(), 1);
        assertEq(game.currentMissionId(), 1);
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.totalMissionsResolved(), 0);
    }

    function test_Immutables() public view {
        assertEq(game.probeFee(), PROBE_FEE);
        assertEq(game.missionFee(), MISSION_FEE);
        assertEq(game.missionInterval(), MISSION_INTERVAL);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
        assertEq(game.initialIntegrity(), INITIAL_INTEGRITY);
        assertEq(game.minIntegrity(), MIN_INTEGRITY);
        assertEq(game.maxProbesPerMission(), MAX_PROBES);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("VoidHarvester: missionInterval=0");
        new VoidHarvesterHarness(
            PROBE_FEE, MISSION_FEE, 0, PROTOCOL_RAKE_BPS,
            INITIAL_INTEGRITY, MIN_INTEGRITY, MAX_PROBES
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("VoidHarvester: rake > 20%");
        new VoidHarvesterHarness(
            PROBE_FEE, MISSION_FEE, MISSION_INTERVAL, 2001,
            INITIAL_INTEGRITY, MIN_INTEGRITY, MAX_PROBES
        );
    }

    function test_ConstructorRejectsBadIntegrityOrdering() public {
        vm.expectRevert("VoidHarvester: integrity ordering");
        new VoidHarvesterHarness(
            PROBE_FEE, MISSION_FEE, MISSION_INTERVAL, PROTOCOL_RAKE_BPS,
            50, 500, MAX_PROBES
        );
    }

    function test_ConstructorRejectsLowMaxProbes() public {
        vm.expectRevert("VoidHarvester: maxProbes < 2");
        new VoidHarvesterHarness(
            PROBE_FEE, MISSION_FEE, MISSION_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_INTEGRITY, MIN_INTEGRITY, 1
        );
    }

    function test_ConstructorRejectsHighMaxProbes() public {
        vm.expectRevert("VoidHarvester: maxProbes > 16");
        new VoidHarvesterHarness(
            PROBE_FEE, MISSION_FEE, MISSION_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_INTEGRITY, MIN_INTEGRITY, 17
        );
    }

    // ===============================================================
    //  Section 3 — Probe deployment
    // ===============================================================

    function test_DeployProbe() public {
        vm.prank(alice);
        uint256 id = game.deployProbe{value: PROBE_FEE}();
        assertEq(id, 1);
        VoidHarvester.Probe memory p = game.getProbe(1);
        assertEq(p.owner, alice);
        assertEq(p.integrity, INITIAL_INTEGRITY);
        assertEq(p.victories, 0);
        assertEq(p.missions, 0);
        assertEq(game.protocolFeeBalance(), PROBE_FEE);
    }

    function test_DeployProbeRejectsInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert("VoidHarvester: insufficient probe fee");
        game.deployProbe{value: PROBE_FEE - 1}();
    }

    function test_DeployProbeRefundsOverpayment() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        game.deployProbe{value: PROBE_FEE + 1 ether}();
        assertEq(alice.balance, before - PROBE_FEE);
    }

    function test_DeployProbeIdsAreSequential() public {
        vm.prank(alice);
        game.deployProbe{value: PROBE_FEE}();
        vm.prank(bob);
        game.deployProbe{value: PROBE_FEE}();
        vm.prank(carol);
        game.deployProbe{value: PROBE_FEE}();

        assertEq(game.nextProbeId(), 4);
        assertEq(game.getProbe(1).owner, alice);
        assertEq(game.getProbe(2).owner, bob);
        assertEq(game.getProbe(3).owner, carol);
    }

    // ===============================================================
    //  Section 4 — Mission launch
    // ===============================================================

    function test_LaunchMission() public {
        _deployProbe(alice);
        vm.prank(alice);
        game.launchMission{value: MISSION_FEE}(1);

        assertEq(game.currentEntrantCount(), 1);
        assertEq(game.currentPrizePool(), MISSION_FEE);
        assertTrue(game.enteredInCurrentMission(1));
    }

    function test_LaunchMissionRejectsNonOwner() public {
        _deployProbe(alice);
        vm.prank(bob);
        vm.expectRevert("VoidHarvester: not owner");
        game.launchMission{value: MISSION_FEE}(1);
    }

    function test_LaunchMissionRejectsDoubleEntry() public {
        _deployProbe(alice);
        vm.prank(alice);
        game.launchMission{value: MISSION_FEE}(1);
        vm.prank(alice);
        vm.expectRevert("VoidHarvester: already launched");
        game.launchMission{value: MISSION_FEE}(1);
    }

    function test_LaunchMissionRejectsInsufficientFee() public {
        _deployProbe(alice);
        vm.prank(alice);
        vm.expectRevert("VoidHarvester: insufficient mission fee");
        game.launchMission{value: MISSION_FEE - 1}(1);
    }

    function test_LaunchMissionRejectsFull() public {
        for (uint256 i = 0; i < MAX_PROBES; i++) {
            address player = vm.addr(0x1000 + i);
            vm.deal(player, 1 ether);
            vm.prank(player);
            uint256 id = game.deployProbe{value: PROBE_FEE}();
            vm.prank(player);
            game.launchMission{value: MISSION_FEE}(id);
        }

        _deployProbe(alice);
        uint256 aliceProbeId = game.nextProbeId() - 1;

        vm.prank(alice);
        vm.expectRevert("VoidHarvester: mission full");
        game.launchMission{value: MISSION_FEE}(aliceProbeId);
    }

    function test_LaunchMissionRefundsOverpayment() public {
        _deployProbe(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        game.launchMission{value: MISSION_FEE + 1 ether}(1);
        assertEq(alice.balance, before - MISSION_FEE);
    }

    // ===============================================================
    //  Section 5 — Mission resolution
    // ===============================================================

    function test_ShouldProgressFalseWithOneProbe() public {
        _deployProbe(alice);
        vm.prank(alice);
        game.launchMission{value: MISSION_FEE}(1);
        vm.warp(block.timestamp + MISSION_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWithTwoProbes() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ShouldProgressFalseBeforeInterval() public {
        _enterPair();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ResolveMissionIncrementsMissionId() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentMissionId(), 2);
    }

    function test_ResolveMissionDistributesPrize() public {
        _enterPair();
        uint256 poolBefore = game.currentPrizePool();
        assertEq(poolBefore, MISSION_FEE * 2);

        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        uint256 expectedRake = (poolBefore * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPrize = poolBefore - expectedRake;

        uint256 withdrawable = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        assertEq(withdrawable, expectedPrize);
        assertEq(game.protocolFeeBalance() - PROBE_FEE * 2, expectedRake);
    }

    function test_ResolveMissionClearsEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertFalse(game.enteredInCurrentMission(1));
        assertFalse(game.enteredInCurrentMission(2));
    }

    function test_ResolveMissionAppliesDecay() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(42)));

        VoidHarvester.Probe memory p1 = game.getProbe(1);
        VoidHarvester.Probe memory p2 = game.getProbe(2);

        assertLt(p1.integrity, INITIAL_INTEGRITY, "decay reduces integrity");
        assertLt(p2.integrity, INITIAL_INTEGRITY, "decay reduces integrity");
        assertGe(p1.integrity, INITIAL_INTEGRITY - 20);
        assertGe(p2.integrity, INITIAL_INTEGRITY - 20);
        assertEq(p1.missions, 1);
        assertEq(p2.missions, 1);
    }

    function test_ResolveMissionIncrementsWinnerVictories() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        VoidHarvester.Probe memory p1 = game.getProbe(1);
        VoidHarvester.Probe memory p2 = game.getProbe(2);
        uint256 totalVictories = p1.victories + p2.victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    function test_ResolveMissionEmitsEvent() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);

        vm.expectEmit(true, false, false, false, address(game));
        emit VoidHarvester.MissionResolved(1, 0, address(0), 0, 0, bytes32(0));
        game.tickForTest(bytes32(uint256(7)));
    }

    function test_ResolveMissionRejectsTooSoon() public {
        _enterPair();
        vm.expectRevert("VoidHarvester: too soon");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveMissionRejectsStaleLoopID() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        vm.expectRevert("VoidHarvester: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    function test_ResolveMissionRejectsNotEnoughProbes() public {
        _deployProbe(alice);
        vm.prank(alice);
        game.launchMission{value: MISSION_FEE}(1);
        vm.warp(block.timestamp + MISSION_INTERVAL);
        vm.expectRevert("VoidHarvester: not enough probes");
        game.tickForTest(bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 6 — Winnings claim (pull-payment)
    // ===============================================================

    function test_ClaimWinnings() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        address winner = game.pendingWithdrawals(alice) > 0 ? alice : bob;
        uint256 pending = game.pendingWithdrawals(winner);
        uint256 before = winner.balance;

        vm.prank(winner);
        game.claimWinnings();

        assertEq(winner.balance - before, pending);
        assertEq(game.pendingWithdrawals(winner), 0);
    }

    function test_ClaimWinningsRejectsZero() public {
        vm.prank(alice);
        vm.expectRevert("VoidHarvester: nothing to claim");
        game.claimWinnings();
    }

    // ===============================================================
    //  Section 7 — Multiple sequential missions
    // ===============================================================

    function test_MultipleMissions() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 5; i++) {
            ts += MISSION_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("mission", i))))
            );

            if (i < 4) {
                vm.prank(alice);
                game.launchMission{value: MISSION_FEE}(1);
                vm.prank(bob);
                game.launchMission{value: MISSION_FEE}(2);
            }
        }

        assertEq(game.totalMissionsResolved(), 5);
        assertEq(game.currentMissionId(), 6);
    }

    function test_DecayDecommissionProbeAfterManyMissions() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 80; i++) {
            ts += MISSION_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("decommission", i))))
            );

            if (game.getProbe(1).integrity > MIN_INTEGRITY && i < 79) {
                vm.prank(alice);
                try game.launchMission{value: MISSION_FEE}(1) {} catch { break; }
                vm.prank(bob);
                try game.launchMission{value: MISSION_FEE}(2) {} catch { break; }
            } else {
                break;
            }
        }

        VoidHarvester.Probe memory p1 = game.getProbe(1);
        assertLt(p1.integrity, INITIAL_INTEGRITY, "decay accrued");
    }

    // ===============================================================
    //  Section 8 — Weighted winner selection
    // ===============================================================

    function test_HigherIntegrityMoreLikelyToWin() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(100)));

        VoidHarvester.Probe memory p1 = game.getProbe(1);
        VoidHarvester.Probe memory p2 = game.getProbe(2);
        assertEq(p1.victories, 1, "probe 1 should win with weight 100");
        assertEq(p2.victories, 0);
    }

    function test_Probe2WinsWithHighWeight() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(bytes32(uint256(600)));

        VoidHarvester.Probe memory p1 = game.getProbe(1);
        VoidHarvester.Probe memory p2 = game.getProbe(2);
        assertEq(p1.victories, 0);
        assertEq(p2.victories, 1);
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _deployProbe(alice);
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, PROBE_FEE);
        assertEq(admin.balance - before, PROBE_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceeds() public {
        vm.expectRevert("VoidHarvester: exceeds balance");
        game.withdrawProtocolFees(admin, 1 ether);
    }

    function test_WithdrawRejectsNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        game.withdrawProtocolFees(alice, 0);
    }

    // ===============================================================
    //  Section 10 — VRF envelope rejection
    // ===============================================================

    function test_RejectsUnregisteredControllerVRFEnvelope() public {
        _enterPair();
        vm.warp(block.timestamp + MISSION_INTERVAL);

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
    //  Section 11 — Fuzz tests
    // ===============================================================

    function testFuzz_MissionSettlementInvariant(bytes32 randomness) public {
        _enterPair();
        uint256 pool = game.currentPrizePool();
        uint256 feeBefore = game.protocolFeeBalance();

        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(randomness);

        uint256 rake = (pool * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 prize = pool - rake;

        uint256 totalPending = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        uint256 feeDelta = game.protocolFeeBalance() - feeBefore;

        assertEq(totalPending, prize, "prize to one winner");
        assertEq(feeDelta, rake, "fee matches rake");
    }

    function testFuzz_DecayBounds(bytes32 randomness) public {
        _enterPair();
        uint32 integrityBefore1 = game.getProbe(1).integrity;
        uint32 integrityBefore2 = game.getProbe(2).integrity;

        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(randomness);

        uint32 decay1 = integrityBefore1 - game.getProbe(1).integrity;
        uint32 decay2 = integrityBefore2 - game.getProbe(2).integrity;

        assertGe(decay1, game.DECAY_MIN());
        assertLe(decay1, game.DECAY_MAX());
        assertGe(decay2, game.DECAY_MIN());
        assertLe(decay2, game.DECAY_MAX());
    }

    function testFuzz_WinnerInBounds(bytes32 randomness) public {
        _deployProbe(alice);
        _deployProbe(bob);
        _deployProbe(carol);

        vm.prank(alice);
        game.launchMission{value: MISSION_FEE}(1);
        vm.prank(bob);
        game.launchMission{value: MISSION_FEE}(2);
        vm.prank(carol);
        game.launchMission{value: MISSION_FEE}(3);

        vm.warp(block.timestamp + MISSION_INTERVAL);
        game.tickForTest(randomness);

        uint256 totalVictories = game.getProbe(1).victories +
            game.getProbe(2).victories +
            game.getProbe(3).victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _deployProbe(address who) internal returns (uint256) {
        vm.prank(who);
        return game.deployProbe{value: PROBE_FEE}();
    }

    function _enterPair() internal {
        _deployProbe(alice);
        _deployProbe(bob);
        vm.prank(alice);
        game.launchMission{value: MISSION_FEE}(1);
        vm.prank(bob);
        game.launchMission{value: MISSION_FEE}(2);
    }
}
