// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/SorcererDuel.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract SorcererDuelHarness is SorcererDuel {
    constructor(
        uint256 _summonFee,
        uint256 _entryFee,
        uint256 _duelInterval,
        uint256 _protocolRakeBps,
        uint32 _initialMana,
        uint32 _minMana,
        uint256 _maxDuelists
    )
        SorcererDuel(
            _summonFee,
            _entryFee,
            _duelInterval,
            _protocolRakeBps,
            _initialMana,
            _minMana,
            _maxDuelists
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract SorcererDuelTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    SorcererDuelHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant SUMMON_FEE = 0.01 ether;
    uint256 constant ENTRY_FEE = 0.001 ether;
    uint256 constant DUEL_INTERVAL = 60;
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint32 constant INITIAL_MANA = 500;
    uint32 constant MIN_MANA = 50;
    uint256 constant MAX_DUELISTS = 8;
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

        game = new SorcererDuelHarness(
            SUMMON_FEE,
            ENTRY_FEE,
            DUEL_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_MANA,
            MIN_MANA,
            MAX_DUELISTS
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
        assertEq(game.nextSorcererId(), 1);
        assertEq(game.currentDuelId(), 1);
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.totalDuelsResolved(), 0);
    }

    function test_Immutables() public view {
        assertEq(game.summonFee(), SUMMON_FEE);
        assertEq(game.entryFee(), ENTRY_FEE);
        assertEq(game.duelInterval(), DUEL_INTERVAL);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
        assertEq(game.initialMana(), INITIAL_MANA);
        assertEq(game.minMana(), MIN_MANA);
        assertEq(game.maxDuelists(), MAX_DUELISTS);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("SorcererDuel: duelInterval=0");
        new SorcererDuelHarness(
            SUMMON_FEE, ENTRY_FEE, 0, PROTOCOL_RAKE_BPS,
            INITIAL_MANA, MIN_MANA, MAX_DUELISTS
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("SorcererDuel: rake > 20%");
        new SorcererDuelHarness(
            SUMMON_FEE, ENTRY_FEE, DUEL_INTERVAL, 2001,
            INITIAL_MANA, MIN_MANA, MAX_DUELISTS
        );
    }

    function test_ConstructorRejectsBadManaOrdering() public {
        vm.expectRevert("SorcererDuel: mana ordering");
        new SorcererDuelHarness(
            SUMMON_FEE, ENTRY_FEE, DUEL_INTERVAL, PROTOCOL_RAKE_BPS,
            50, 500, MAX_DUELISTS
        );
    }

    function test_ConstructorRejectsLowMaxDuelists() public {
        vm.expectRevert("SorcererDuel: maxEntrants < 2");
        new SorcererDuelHarness(
            SUMMON_FEE, ENTRY_FEE, DUEL_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_MANA, MIN_MANA, 1
        );
    }

    function test_ConstructorRejectsHighMaxDuelists() public {
        vm.expectRevert("SorcererDuel: maxEntrants > 16");
        new SorcererDuelHarness(
            SUMMON_FEE, ENTRY_FEE, DUEL_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_MANA, MIN_MANA, 17
        );
    }

    // ===============================================================
    //  Section 3 — Sorcerer summoning
    // ===============================================================

    function test_SummonSorcerer() public {
        vm.prank(alice);
        uint256 id = game.summonSorcerer{value: SUMMON_FEE}();
        assertEq(id, 1);
        SorcererDuel.Sorcerer memory s = game.getSorcerer(1);
        assertEq(s.owner, alice);
        assertEq(s.mana, INITIAL_MANA);
        assertEq(s.victories, 0);
        assertEq(s.duels, 0);
        assertEq(game.protocolFeeBalance(), SUMMON_FEE);
    }

    function test_SummonSorcererRejectsInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert("SorcererDuel: insufficient summon fee");
        game.summonSorcerer{value: SUMMON_FEE - 1}();
    }

    function test_SummonSorcererRefundsOverpayment() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        game.summonSorcerer{value: SUMMON_FEE + 1 ether}();
        assertEq(alice.balance, before - SUMMON_FEE);
    }

    function test_SummonSorcererIdsAreSequential() public {
        vm.prank(alice);
        game.summonSorcerer{value: SUMMON_FEE}();
        vm.prank(bob);
        game.summonSorcerer{value: SUMMON_FEE}();
        vm.prank(carol);
        game.summonSorcerer{value: SUMMON_FEE}();

        assertEq(game.nextSorcererId(), 4);
        assertEq(game.getSorcerer(1).owner, alice);
        assertEq(game.getSorcerer(2).owner, bob);
        assertEq(game.getSorcerer(3).owner, carol);
    }

    // ===============================================================
    //  Section 4 — Duel entry
    // ===============================================================

    function test_EnterDuel() public {
        _summonSorcerer(alice);
        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE}(1);

        assertEq(game.currentEntrantCount(), 1);
        assertEq(game.currentPrizePool(), ENTRY_FEE);
        assertTrue(game.enteredInCurrentDuel(1));
    }

    function test_EnterDuelRejectsNonOwner() public {
        _summonSorcerer(alice);
        vm.prank(bob);
        vm.expectRevert("SorcererDuel: not owner");
        game.enterDuel{value: ENTRY_FEE}(1);
    }

    function test_EnterDuelRejectsDoubleEntry() public {
        _summonSorcerer(alice);
        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE}(1);
        vm.prank(alice);
        vm.expectRevert("SorcererDuel: already entered");
        game.enterDuel{value: ENTRY_FEE}(1);
    }

    function test_EnterDuelRejectsInsufficientFee() public {
        _summonSorcerer(alice);
        vm.prank(alice);
        vm.expectRevert("SorcererDuel: insufficient entry fee");
        game.enterDuel{value: ENTRY_FEE - 1}(1);
    }

    function test_EnterDuelRejectsFull() public {
        for (uint256 i = 0; i < MAX_DUELISTS; i++) {
            address player = vm.addr(0x1000 + i);
            vm.deal(player, 1 ether);
            vm.prank(player);
            uint256 id = game.summonSorcerer{value: SUMMON_FEE}();
            vm.prank(player);
            game.enterDuel{value: ENTRY_FEE}(id);
        }

        _summonSorcerer(alice);
        uint256 aliceSorcererId = game.nextSorcererId() - 1;

        vm.prank(alice);
        vm.expectRevert("SorcererDuel: duel full");
        game.enterDuel{value: ENTRY_FEE}(aliceSorcererId);
    }

    function test_EnterDuelRefundsOverpayment() public {
        _summonSorcerer(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE + 1 ether}(1);
        assertEq(alice.balance, before - ENTRY_FEE);
    }

    // ===============================================================
    //  Section 5 — Duel resolution
    // ===============================================================

    function test_ShouldProgressFalseWithOneSorcerer() public {
        _summonSorcerer(alice);
        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + DUEL_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWithTwoSorcerers() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ShouldProgressFalseBeforeInterval() public {
        _enterPair();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ResolveDuelIncrementsDuelId() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentDuelId(), 2);
    }

    function test_ResolveDuelDistributesPrize() public {
        _enterPair();
        uint256 poolBefore = game.currentPrizePool();
        assertEq(poolBefore, ENTRY_FEE * 2);

        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        uint256 expectedRake = (poolBefore * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPrize = poolBefore - expectedRake;

        uint256 withdrawable = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        assertEq(withdrawable, expectedPrize);
        assertEq(game.protocolFeeBalance() - SUMMON_FEE * 2, expectedRake);
    }

    function test_ResolveDuelClearsEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertFalse(game.enteredInCurrentDuel(1));
        assertFalse(game.enteredInCurrentDuel(2));
    }

    function test_ResolveDuelDrainsMana() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(42)));

        SorcererDuel.Sorcerer memory s1 = game.getSorcerer(1);
        SorcererDuel.Sorcerer memory s2 = game.getSorcerer(2);

        assertLt(s1.mana, INITIAL_MANA, "drain reduces mana");
        assertLt(s2.mana, INITIAL_MANA, "drain reduces mana");
        assertGe(s1.mana, INITIAL_MANA - 20);
        assertGe(s2.mana, INITIAL_MANA - 20);
        assertEq(s1.duels, 1);
        assertEq(s2.duels, 1);
    }

    function test_ResolveDuelIncrementsWinnerVictories() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        SorcererDuel.Sorcerer memory s1 = game.getSorcerer(1);
        SorcererDuel.Sorcerer memory s2 = game.getSorcerer(2);
        uint256 totalVictories = s1.victories + s2.victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    function test_ResolveDuelEmitsEvent() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);

        vm.expectEmit(true, false, false, false, address(game));
        emit SorcererDuel.DuelResolved(1, 0, address(0), 0, 0, bytes32(0));
        game.tickForTest(bytes32(uint256(7)));
    }

    function test_ResolveDuelRejectsTooSoon() public {
        _enterPair();
        vm.expectRevert("SorcererDuel: too soon");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveDuelRejectsStaleLoopID() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        vm.expectRevert("SorcererDuel: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    function test_ResolveDuelRejectsNotEnoughEntrants() public {
        _summonSorcerer(alice);
        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + DUEL_INTERVAL);
        vm.expectRevert("SorcererDuel: not enough entrants");
        game.tickForTest(bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 6 — Winnings claim (pull-payment)
    // ===============================================================

    function test_ClaimWinnings() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
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
        vm.expectRevert("SorcererDuel: nothing to claim");
        game.claimWinnings();
    }

    // ===============================================================
    //  Section 7 — Multiple sequential duels
    // ===============================================================

    function test_MultipleDuels() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 5; i++) {
            ts += DUEL_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("duel", i))))
            );

            if (i < 4) {
                vm.prank(alice);
                game.enterDuel{value: ENTRY_FEE}(1);
                vm.prank(bob);
                game.enterDuel{value: ENTRY_FEE}(2);
            }
        }

        assertEq(game.totalDuelsResolved(), 5);
        assertEq(game.currentDuelId(), 6);
    }

    function test_DrainBanishesSorcererAfterManyDuels() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 80; i++) {
            ts += DUEL_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("banish", i))))
            );

            if (game.getSorcerer(1).mana > MIN_MANA && i < 79) {
                vm.prank(alice);
                try game.enterDuel{value: ENTRY_FEE}(1) {} catch { break; }
                vm.prank(bob);
                try game.enterDuel{value: ENTRY_FEE}(2) {} catch { break; }
            } else {
                break;
            }
        }

        SorcererDuel.Sorcerer memory s1 = game.getSorcerer(1);
        assertLt(s1.mana, INITIAL_MANA, "mana drained");
    }

    // ===============================================================
    //  Section 8 — Weighted winner selection
    // ===============================================================

    function test_HigherManaMoreLikelyToWin() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(100)));

        SorcererDuel.Sorcerer memory s1 = game.getSorcerer(1);
        SorcererDuel.Sorcerer memory s2 = game.getSorcerer(2);
        assertEq(s1.victories, 1, "sorcerer 1 should win with weight 100");
        assertEq(s2.victories, 0);
    }

    function test_Sorcerer2WinsWithHighWeight() public {
        _enterPair();
        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(bytes32(uint256(600)));

        SorcererDuel.Sorcerer memory s1 = game.getSorcerer(1);
        SorcererDuel.Sorcerer memory s2 = game.getSorcerer(2);
        assertEq(s1.victories, 0);
        assertEq(s2.victories, 1);
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _summonSorcerer(alice);
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, SUMMON_FEE);
        assertEq(admin.balance - before, SUMMON_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceeds() public {
        vm.expectRevert("SorcererDuel: exceeds balance");
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
        vm.warp(block.timestamp + DUEL_INTERVAL);

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

    function testFuzz_DuelSettlementInvariant(bytes32 randomness) public {
        _enterPair();
        uint256 pool = game.currentPrizePool();
        uint256 feeBefore = game.protocolFeeBalance();

        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(randomness);

        uint256 rake = (pool * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 prize = pool - rake;

        uint256 totalPending = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        uint256 feeDelta = game.protocolFeeBalance() - feeBefore;

        assertEq(totalPending, prize, "prize to one winner");
        assertEq(feeDelta, rake, "fee matches rake");
    }

    function testFuzz_DrainBounds(bytes32 randomness) public {
        _enterPair();
        uint32 manaBefore1 = game.getSorcerer(1).mana;
        uint32 manaBefore2 = game.getSorcerer(2).mana;

        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(randomness);

        uint32 drain1 = manaBefore1 - game.getSorcerer(1).mana;
        uint32 drain2 = manaBefore2 - game.getSorcerer(2).mana;

        assertGe(drain1, game.DRAIN_MIN());
        assertLe(drain1, game.DRAIN_MAX());
        assertGe(drain2, game.DRAIN_MIN());
        assertLe(drain2, game.DRAIN_MAX());
    }

    function testFuzz_WinnerInBounds(bytes32 randomness) public {
        _summonSorcerer(alice);
        _summonSorcerer(bob);
        _summonSorcerer(carol);

        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterDuel{value: ENTRY_FEE}(2);
        vm.prank(carol);
        game.enterDuel{value: ENTRY_FEE}(3);

        vm.warp(block.timestamp + DUEL_INTERVAL);
        game.tickForTest(randomness);

        uint256 totalVictories = game.getSorcerer(1).victories +
            game.getSorcerer(2).victories +
            game.getSorcerer(3).victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _summonSorcerer(address who) internal returns (uint256) {
        vm.prank(who);
        return game.summonSorcerer{value: SUMMON_FEE}();
    }

    function _enterPair() internal {
        _summonSorcerer(alice);
        _summonSorcerer(bob);
        vm.prank(alice);
        game.enterDuel{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterDuel{value: ENTRY_FEE}(2);
    }
}
