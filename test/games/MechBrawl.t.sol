// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/MechBrawl.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract MechBrawlHarness is MechBrawl {
    constructor(
        uint256 _deployFee,
        uint256 _entryFee,
        uint256 _brawlInterval,
        uint256 _protocolRakeBps,
        uint32 _initialArmor,
        uint32 _minArmor,
        uint256 _maxEntrantsPerBrawl
    )
        MechBrawl(
            _deployFee,
            _entryFee,
            _brawlInterval,
            _protocolRakeBps,
            _initialArmor,
            _minArmor,
            _maxEntrantsPerBrawl
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract MechBrawlTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    MechBrawlHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant DEPLOY_FEE = 0.01 ether;
    uint256 constant ENTRY_FEE = 0.001 ether;
    uint256 constant BRAWL_INTERVAL = 60;
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint32 constant INITIAL_ARMOR = 500;
    uint32 constant MIN_ARMOR = 50;
    uint256 constant MAX_ENTRANTS = 8;
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

        game = new MechBrawlHarness(
            DEPLOY_FEE,
            ENTRY_FEE,
            BRAWL_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_ARMOR,
            MIN_ARMOR,
            MAX_ENTRANTS
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
        assertEq(game.nextMechId(), 1);
        assertEq(game.currentBrawlId(), 1);
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.totalBrawlsResolved(), 0);
    }

    function test_Immutables() public view {
        assertEq(game.deployFee(), DEPLOY_FEE);
        assertEq(game.entryFee(), ENTRY_FEE);
        assertEq(game.brawlInterval(), BRAWL_INTERVAL);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
        assertEq(game.initialArmor(), INITIAL_ARMOR);
        assertEq(game.minArmor(), MIN_ARMOR);
        assertEq(game.maxEntrantsPerBrawl(), MAX_ENTRANTS);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("MechBrawl: brawlInterval=0");
        new MechBrawlHarness(
            DEPLOY_FEE, ENTRY_FEE, 0, PROTOCOL_RAKE_BPS,
            INITIAL_ARMOR, MIN_ARMOR, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("MechBrawl: rake > 20%");
        new MechBrawlHarness(
            DEPLOY_FEE, ENTRY_FEE, BRAWL_INTERVAL, 2001,
            INITIAL_ARMOR, MIN_ARMOR, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsBadArmorOrdering() public {
        vm.expectRevert("MechBrawl: armor ordering");
        new MechBrawlHarness(
            DEPLOY_FEE, ENTRY_FEE, BRAWL_INTERVAL, PROTOCOL_RAKE_BPS,
            50, 500, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsLowMaxEntrants() public {
        vm.expectRevert("MechBrawl: maxEntrants < 2");
        new MechBrawlHarness(
            DEPLOY_FEE, ENTRY_FEE, BRAWL_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_ARMOR, MIN_ARMOR, 1
        );
    }

    function test_ConstructorRejectsHighMaxEntrants() public {
        vm.expectRevert("MechBrawl: maxEntrants > 16");
        new MechBrawlHarness(
            DEPLOY_FEE, ENTRY_FEE, BRAWL_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_ARMOR, MIN_ARMOR, 17
        );
    }

    // ===============================================================
    //  Section 3 — Mech deployment
    // ===============================================================

    function test_DeployMech() public {
        vm.prank(alice);
        uint256 id = game.deployMech{value: DEPLOY_FEE}();
        assertEq(id, 1);
        MechBrawl.Mech memory m = game.getMech(1);
        assertEq(m.owner, alice);
        assertEq(m.armor, INITIAL_ARMOR);
        assertEq(m.victories, 0);
        assertEq(m.brawls, 0);
        assertEq(game.protocolFeeBalance(), DEPLOY_FEE);
    }

    function test_DeployMechRejectsInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert("MechBrawl: insufficient deploy fee");
        game.deployMech{value: DEPLOY_FEE - 1}();
    }

    function test_DeployMechRefundsOverpayment() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        game.deployMech{value: DEPLOY_FEE + 1 ether}();
        assertEq(alice.balance, before - DEPLOY_FEE);
    }

    function test_DeployMechIdsAreSequential() public {
        vm.prank(alice);
        game.deployMech{value: DEPLOY_FEE}();
        vm.prank(bob);
        game.deployMech{value: DEPLOY_FEE}();
        vm.prank(carol);
        game.deployMech{value: DEPLOY_FEE}();

        assertEq(game.nextMechId(), 4);
        assertEq(game.getMech(1).owner, alice);
        assertEq(game.getMech(2).owner, bob);
        assertEq(game.getMech(3).owner, carol);
    }

    // ===============================================================
    //  Section 4 — Brawl entry
    // ===============================================================

    function test_JoinBrawl() public {
        _deployMech(alice);
        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE}(1);

        assertEq(game.currentEntrantCount(), 1);
        assertEq(game.currentPrizePool(), ENTRY_FEE);
        assertTrue(game.enteredInCurrentBrawl(1));
    }

    function test_JoinBrawlRejectsNonOwner() public {
        _deployMech(alice);
        vm.prank(bob);
        vm.expectRevert("MechBrawl: not owner");
        game.joinBrawl{value: ENTRY_FEE}(1);
    }

    function test_JoinBrawlRejectsDoubleEntry() public {
        _deployMech(alice);
        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE}(1);
        vm.prank(alice);
        vm.expectRevert("MechBrawl: already entered");
        game.joinBrawl{value: ENTRY_FEE}(1);
    }

    function test_JoinBrawlRejectsInsufficientFee() public {
        _deployMech(alice);
        vm.prank(alice);
        vm.expectRevert("MechBrawl: insufficient entry fee");
        game.joinBrawl{value: ENTRY_FEE - 1}(1);
    }

    function test_JoinBrawlRejectsFull() public {
        for (uint256 i = 0; i < MAX_ENTRANTS; i++) {
            address player = vm.addr(0x1000 + i);
            vm.deal(player, 1 ether);
            vm.prank(player);
            uint256 id = game.deployMech{value: DEPLOY_FEE}();
            vm.prank(player);
            game.joinBrawl{value: ENTRY_FEE}(id);
        }

        _deployMech(alice);
        uint256 aliceMechId = game.nextMechId() - 1;

        vm.prank(alice);
        vm.expectRevert("MechBrawl: brawl full");
        game.joinBrawl{value: ENTRY_FEE}(aliceMechId);
    }

    function test_JoinBrawlRefundsOverpayment() public {
        _deployMech(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE + 1 ether}(1);
        assertEq(alice.balance, before - ENTRY_FEE);
    }

    // ===============================================================
    //  Section 5 — Brawl resolution
    // ===============================================================

    function test_ShouldProgressFalseWithOneMech() public {
        _deployMech(alice);
        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWithTwoMechs() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ShouldProgressFalseBeforeInterval() public {
        _enterPair();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ResolveBrawlIncrementsBrawlId() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentBrawlId(), 2);
    }

    function test_ResolveBrawlDistributesPrize() public {
        _enterPair();
        uint256 poolBefore = game.currentPrizePool();
        assertEq(poolBefore, ENTRY_FEE * 2);

        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        uint256 expectedRake = (poolBefore * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPrize = poolBefore - expectedRake;

        uint256 withdrawable = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        assertEq(withdrawable, expectedPrize);
        assertEq(game.protocolFeeBalance() - DEPLOY_FEE * 2, expectedRake);
    }

    function test_ResolveBrawlClearsEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertFalse(game.enteredInCurrentBrawl(1));
        assertFalse(game.enteredInCurrentBrawl(2));
    }

    function test_ResolveBrawlAppliesHullDamage() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(42)));

        MechBrawl.Mech memory m1 = game.getMech(1);
        MechBrawl.Mech memory m2 = game.getMech(2);

        assertLt(m1.armor, INITIAL_ARMOR, "damage reduces armor");
        assertLt(m2.armor, INITIAL_ARMOR, "damage reduces armor");
        assertGe(m1.armor, INITIAL_ARMOR - 20);
        assertGe(m2.armor, INITIAL_ARMOR - 20);
        assertEq(m1.brawls, 1);
        assertEq(m2.brawls, 1);
    }

    function test_ResolveBrawlIncrementsWinnerVictories() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        MechBrawl.Mech memory m1 = game.getMech(1);
        MechBrawl.Mech memory m2 = game.getMech(2);
        uint256 totalVictories = m1.victories + m2.victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    function test_ResolveBrawlEmitsEvent() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);

        vm.expectEmit(true, false, false, false, address(game));
        emit MechBrawl.BrawlResolved(1, 0, address(0), 0, 0, bytes32(0));
        game.tickForTest(bytes32(uint256(7)));
    }

    function test_ResolveBrawlRejectsTooSoon() public {
        _enterPair();
        vm.expectRevert("MechBrawl: too soon");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveBrawlRejectsStaleLoopID() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        vm.expectRevert("MechBrawl: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    function test_ResolveBrawlRejectsNotEnoughEntrants() public {
        _deployMech(alice);
        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        vm.expectRevert("MechBrawl: not enough entrants");
        game.tickForTest(bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 6 — Winnings claim (pull-payment)
    // ===============================================================

    function test_ClaimWinnings() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
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
        vm.expectRevert("MechBrawl: nothing to claim");
        game.claimWinnings();
    }

    // ===============================================================
    //  Section 7 — Multiple sequential brawls
    // ===============================================================

    function test_MultipleBrawls() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 5; i++) {
            ts += BRAWL_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("brawl", i))))
            );

            if (i < 4) {
                vm.prank(alice);
                game.joinBrawl{value: ENTRY_FEE}(1);
                vm.prank(bob);
                game.joinBrawl{value: ENTRY_FEE}(2);
            }
        }

        assertEq(game.totalBrawlsResolved(), 5);
        assertEq(game.currentBrawlId(), 6);
    }

    function test_DamageScrapsMechAfterManyBrawls() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 80; i++) {
            ts += BRAWL_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("scrap", i))))
            );

            if (game.getMech(1).armor > MIN_ARMOR && i < 79) {
                vm.prank(alice);
                try game.joinBrawl{value: ENTRY_FEE}(1) {} catch { break; }
                vm.prank(bob);
                try game.joinBrawl{value: ENTRY_FEE}(2) {} catch { break; }
            } else {
                break;
            }
        }

        MechBrawl.Mech memory m1 = game.getMech(1);
        assertLt(m1.armor, INITIAL_ARMOR, "damage accrued");
    }

    // ===============================================================
    //  Section 8 — Weighted winner selection
    // ===============================================================

    function test_HigherArmorMoreLikelyToWin() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(100)));

        MechBrawl.Mech memory m1 = game.getMech(1);
        MechBrawl.Mech memory m2 = game.getMech(2);
        assertEq(m1.victories, 1, "mech 1 should win with weight 100");
        assertEq(m2.victories, 0);
    }

    function test_Mech2WinsWithHighWeight() public {
        _enterPair();
        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(bytes32(uint256(600)));

        MechBrawl.Mech memory m1 = game.getMech(1);
        MechBrawl.Mech memory m2 = game.getMech(2);
        assertEq(m1.victories, 0);
        assertEq(m2.victories, 1);
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _deployMech(alice);
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, DEPLOY_FEE);
        assertEq(admin.balance - before, DEPLOY_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceeds() public {
        vm.expectRevert("MechBrawl: exceeds balance");
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
        vm.warp(block.timestamp + BRAWL_INTERVAL);

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

    function testFuzz_BrawlSettlementInvariant(bytes32 randomness) public {
        _enterPair();
        uint256 pool = game.currentPrizePool();
        uint256 feeBefore = game.protocolFeeBalance();

        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(randomness);

        uint256 rake = (pool * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 prize = pool - rake;

        uint256 totalPending = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        uint256 feeDelta = game.protocolFeeBalance() - feeBefore;

        assertEq(totalPending, prize, "prize to one winner");
        assertEq(feeDelta, rake, "fee matches rake");
    }

    function testFuzz_DamageBounds(bytes32 randomness) public {
        _enterPair();
        uint32 armorBefore1 = game.getMech(1).armor;
        uint32 armorBefore2 = game.getMech(2).armor;

        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(randomness);

        uint32 damage1 = armorBefore1 - game.getMech(1).armor;
        uint32 damage2 = armorBefore2 - game.getMech(2).armor;

        assertGe(damage1, game.DAMAGE_MIN());
        assertLe(damage1, game.DAMAGE_MAX());
        assertGe(damage2, game.DAMAGE_MIN());
        assertLe(damage2, game.DAMAGE_MAX());
    }

    function testFuzz_WinnerInBounds(bytes32 randomness) public {
        _deployMech(alice);
        _deployMech(bob);
        _deployMech(carol);

        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.joinBrawl{value: ENTRY_FEE}(2);
        vm.prank(carol);
        game.joinBrawl{value: ENTRY_FEE}(3);

        vm.warp(block.timestamp + BRAWL_INTERVAL);
        game.tickForTest(randomness);

        uint256 totalVictories = game.getMech(1).victories +
            game.getMech(2).victories +
            game.getMech(3).victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _deployMech(address who) internal returns (uint256) {
        vm.prank(who);
        return game.deployMech{value: DEPLOY_FEE}();
    }

    function _enterPair() internal {
        _deployMech(alice);
        _deployMech(bob);
        vm.prank(alice);
        game.joinBrawl{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.joinBrawl{value: ENTRY_FEE}(2);
    }
}
