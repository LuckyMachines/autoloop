// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/KaijuLeague.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract KaijuLeagueHarness is KaijuLeague {
    constructor(
        uint256 _hatchFee,
        uint256 _entryFee,
        uint256 _clashInterval,
        uint256 _protocolRakeBps,
        uint32 _initialHealth,
        uint32 _minHealth,
        uint256 _maxEntrantsPerClash
    )
        KaijuLeague(
            _hatchFee,
            _entryFee,
            _clashInterval,
            _protocolRakeBps,
            _initialHealth,
            _minHealth,
            _maxEntrantsPerClash
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract KaijuLeagueTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    KaijuLeagueHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant HATCH_FEE = 0.01 ether;
    uint256 constant ENTRY_FEE = 0.001 ether;
    uint256 constant CLASH_INTERVAL = 60;
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint32 constant INITIAL_HEALTH = 500;
    uint32 constant MIN_HEALTH = 50;
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

        game = new KaijuLeagueHarness(
            HATCH_FEE,
            ENTRY_FEE,
            CLASH_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_HEALTH,
            MIN_HEALTH,
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
        assertEq(game.nextKaijuId(), 1);
        assertEq(game.currentClashId(), 1);
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.totalClashesResolved(), 0);
    }

    function test_Immutables() public view {
        assertEq(game.hatchFee(), HATCH_FEE);
        assertEq(game.entryFee(), ENTRY_FEE);
        assertEq(game.clashInterval(), CLASH_INTERVAL);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
        assertEq(game.initialHealth(), INITIAL_HEALTH);
        assertEq(game.minHealth(), MIN_HEALTH);
        assertEq(game.maxEntrantsPerClash(), MAX_ENTRANTS);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("KaijuLeague: clashInterval=0");
        new KaijuLeagueHarness(
            HATCH_FEE, ENTRY_FEE, 0, PROTOCOL_RAKE_BPS,
            INITIAL_HEALTH, MIN_HEALTH, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("KaijuLeague: rake > 20%");
        new KaijuLeagueHarness(
            HATCH_FEE, ENTRY_FEE, CLASH_INTERVAL, 2001,
            INITIAL_HEALTH, MIN_HEALTH, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsBadHealthOrdering() public {
        vm.expectRevert("KaijuLeague: health ordering");
        new KaijuLeagueHarness(
            HATCH_FEE, ENTRY_FEE, CLASH_INTERVAL, PROTOCOL_RAKE_BPS,
            50, 500, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsLowMaxEntrants() public {
        vm.expectRevert("KaijuLeague: maxEntrants < 2");
        new KaijuLeagueHarness(
            HATCH_FEE, ENTRY_FEE, CLASH_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_HEALTH, MIN_HEALTH, 1
        );
    }

    function test_ConstructorRejectsHighMaxEntrants() public {
        vm.expectRevert("KaijuLeague: maxEntrants > 16");
        new KaijuLeagueHarness(
            HATCH_FEE, ENTRY_FEE, CLASH_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_HEALTH, MIN_HEALTH, 17
        );
    }

    // ===============================================================
    //  Section 3 — Kaiju hatching
    // ===============================================================

    function test_HatchKaiju() public {
        vm.prank(alice);
        uint256 id = game.hatchKaiju{value: HATCH_FEE}();
        assertEq(id, 1);
        KaijuLeague.Kaiju memory k = game.getKaiju(1);
        assertEq(k.owner, alice);
        assertEq(k.health, INITIAL_HEALTH);
        assertEq(k.victories, 0);
        assertEq(k.clashes, 0);
        assertEq(game.protocolFeeBalance(), HATCH_FEE);
    }

    function test_HatchKaijuRejectsInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert("KaijuLeague: insufficient hatch fee");
        game.hatchKaiju{value: HATCH_FEE - 1}();
    }

    function test_HatchKaijuRefundsOverpayment() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        game.hatchKaiju{value: HATCH_FEE + 1 ether}();
        assertEq(alice.balance, before - HATCH_FEE);
    }

    function test_HatchKaijuIdsAreSequential() public {
        vm.prank(alice);
        game.hatchKaiju{value: HATCH_FEE}();
        vm.prank(bob);
        game.hatchKaiju{value: HATCH_FEE}();
        vm.prank(carol);
        game.hatchKaiju{value: HATCH_FEE}();

        assertEq(game.nextKaijuId(), 4);
        assertEq(game.getKaiju(1).owner, alice);
        assertEq(game.getKaiju(2).owner, bob);
        assertEq(game.getKaiju(3).owner, carol);
    }

    // ===============================================================
    //  Section 4 — Clash entry
    // ===============================================================

    function test_EnterClash() public {
        _hatchKaiju(alice);
        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE}(1);

        assertEq(game.currentEntrantCount(), 1);
        assertEq(game.currentPrizePool(), ENTRY_FEE);
        assertTrue(game.enteredInCurrentClash(1));
    }

    function test_EnterClashRejectsNonOwner() public {
        _hatchKaiju(alice);
        vm.prank(bob);
        vm.expectRevert("KaijuLeague: not owner");
        game.enterClash{value: ENTRY_FEE}(1);
    }

    function test_EnterClashRejectsDoubleEntry() public {
        _hatchKaiju(alice);
        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE}(1);
        vm.prank(alice);
        vm.expectRevert("KaijuLeague: already entered");
        game.enterClash{value: ENTRY_FEE}(1);
    }

    function test_EnterClashRejectsInsufficientFee() public {
        _hatchKaiju(alice);
        vm.prank(alice);
        vm.expectRevert("KaijuLeague: insufficient entry fee");
        game.enterClash{value: ENTRY_FEE - 1}(1);
    }

    function test_EnterClashRejectsFull() public {
        for (uint256 i = 0; i < MAX_ENTRANTS; i++) {
            address player = vm.addr(0x1000 + i);
            vm.deal(player, 1 ether);
            vm.prank(player);
            uint256 id = game.hatchKaiju{value: HATCH_FEE}();
            vm.prank(player);
            game.enterClash{value: ENTRY_FEE}(id);
        }

        _hatchKaiju(alice);
        uint256 aliceKaijuId = game.nextKaijuId() - 1;

        vm.prank(alice);
        vm.expectRevert("KaijuLeague: clash full");
        game.enterClash{value: ENTRY_FEE}(aliceKaijuId);
    }

    function test_EnterClashRefundsOverpayment() public {
        _hatchKaiju(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE + 1 ether}(1);
        assertEq(alice.balance, before - ENTRY_FEE);
    }

    // ===============================================================
    //  Section 5 — Clash resolution
    // ===============================================================

    function test_ShouldProgressFalseWithOneKaiju() public {
        _hatchKaiju(alice);
        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + CLASH_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWithTwoKaiju() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ShouldProgressFalseBeforeInterval() public {
        _enterPair();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ResolveClashIncrementsClashId() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentClashId(), 2);
    }

    function test_ResolveClashDistributesPrize() public {
        _enterPair();
        uint256 poolBefore = game.currentPrizePool();
        assertEq(poolBefore, ENTRY_FEE * 2);

        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        uint256 expectedRake = (poolBefore * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPrize = poolBefore - expectedRake;

        uint256 withdrawable = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        assertEq(withdrawable, expectedPrize);
        assertEq(game.protocolFeeBalance() - HATCH_FEE * 2, expectedRake);
    }

    function test_ResolveClashClearsEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertFalse(game.enteredInCurrentClash(1));
        assertFalse(game.enteredInCurrentClash(2));
    }

    function test_ResolveClashAppliesDamage() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(42)));

        KaijuLeague.Kaiju memory k1 = game.getKaiju(1);
        KaijuLeague.Kaiju memory k2 = game.getKaiju(2);

        assertLt(k1.health, INITIAL_HEALTH, "damage reduces health");
        assertLt(k2.health, INITIAL_HEALTH, "damage reduces health");
        assertGe(k1.health, INITIAL_HEALTH - 20);
        assertGe(k2.health, INITIAL_HEALTH - 20);
        assertEq(k1.clashes, 1);
        assertEq(k2.clashes, 1);
    }

    function test_ResolveClashIncrementsWinnerVictories() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        KaijuLeague.Kaiju memory k1 = game.getKaiju(1);
        KaijuLeague.Kaiju memory k2 = game.getKaiju(2);
        uint256 totalVictories = k1.victories + k2.victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    function test_ResolveClashEmitsEvent() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);

        vm.expectEmit(true, false, false, false, address(game));
        emit KaijuLeague.ClashResolved(1, 0, address(0), 0, 0, bytes32(0));
        game.tickForTest(bytes32(uint256(7)));
    }

    function test_ResolveClashRejectsTooSoon() public {
        _enterPair();
        vm.expectRevert("KaijuLeague: too soon");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveClashRejectsStaleLoopID() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        vm.expectRevert("KaijuLeague: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    function test_ResolveClashRejectsNotEnoughEntrants() public {
        _hatchKaiju(alice);
        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + CLASH_INTERVAL);
        vm.expectRevert("KaijuLeague: not enough entrants");
        game.tickForTest(bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 6 — Winnings claim (pull-payment)
    // ===============================================================

    function test_ClaimWinnings() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
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
        vm.expectRevert("KaijuLeague: nothing to claim");
        game.claimWinnings();
    }

    // ===============================================================
    //  Section 7 — Multiple sequential clashes
    // ===============================================================

    function test_MultipleClashes() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 5; i++) {
            ts += CLASH_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("clash", i))))
            );

            if (i < 4) {
                vm.prank(alice);
                game.enterClash{value: ENTRY_FEE}(1);
                vm.prank(bob);
                game.enterClash{value: ENTRY_FEE}(2);
            }
        }

        assertEq(game.totalClashesResolved(), 5);
        assertEq(game.currentClashId(), 6);
    }

    function test_DamageDestroysKaijuAfterManyClashes() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 80; i++) {
            ts += CLASH_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("destroy", i))))
            );

            if (game.getKaiju(1).health > MIN_HEALTH && i < 79) {
                vm.prank(alice);
                try game.enterClash{value: ENTRY_FEE}(1) {} catch { break; }
                vm.prank(bob);
                try game.enterClash{value: ENTRY_FEE}(2) {} catch { break; }
            } else {
                break;
            }
        }

        KaijuLeague.Kaiju memory k1 = game.getKaiju(1);
        assertLt(k1.health, INITIAL_HEALTH, "damage accrued");
    }

    // ===============================================================
    //  Section 8 — Weighted winner selection
    // ===============================================================

    function test_HigherHealthMoreLikelyToWin() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(100)));

        KaijuLeague.Kaiju memory k1 = game.getKaiju(1);
        KaijuLeague.Kaiju memory k2 = game.getKaiju(2);
        assertEq(k1.victories, 1, "kaiju 1 should win with weight 100");
        assertEq(k2.victories, 0);
    }

    function test_Kaiju2WinsWithHighWeight() public {
        _enterPair();
        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(bytes32(uint256(600)));

        KaijuLeague.Kaiju memory k1 = game.getKaiju(1);
        KaijuLeague.Kaiju memory k2 = game.getKaiju(2);
        assertEq(k1.victories, 0);
        assertEq(k2.victories, 1);
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _hatchKaiju(alice);
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, HATCH_FEE);
        assertEq(admin.balance - before, HATCH_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceeds() public {
        vm.expectRevert("KaijuLeague: exceeds balance");
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
        vm.warp(block.timestamp + CLASH_INTERVAL);

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

    function testFuzz_ClashSettlementInvariant(bytes32 randomness) public {
        _enterPair();
        uint256 pool = game.currentPrizePool();
        uint256 feeBefore = game.protocolFeeBalance();

        vm.warp(block.timestamp + CLASH_INTERVAL);
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
        uint32 healthBefore1 = game.getKaiju(1).health;
        uint32 healthBefore2 = game.getKaiju(2).health;

        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(randomness);

        uint32 damage1 = healthBefore1 - game.getKaiju(1).health;
        uint32 damage2 = healthBefore2 - game.getKaiju(2).health;

        assertGe(damage1, game.DAMAGE_MIN());
        assertLe(damage1, game.DAMAGE_MAX());
        assertGe(damage2, game.DAMAGE_MIN());
        assertLe(damage2, game.DAMAGE_MAX());
    }

    function testFuzz_WinnerInBounds(bytes32 randomness) public {
        _hatchKaiju(alice);
        _hatchKaiju(bob);
        _hatchKaiju(carol);

        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterClash{value: ENTRY_FEE}(2);
        vm.prank(carol);
        game.enterClash{value: ENTRY_FEE}(3);

        vm.warp(block.timestamp + CLASH_INTERVAL);
        game.tickForTest(randomness);

        uint256 totalVictories = game.getKaiju(1).victories +
            game.getKaiju(2).victories +
            game.getKaiju(3).victories;
        assertEq(totalVictories, 1, "exactly one winner");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _hatchKaiju(address who) internal returns (uint256) {
        vm.prank(who);
        return game.hatchKaiju{value: HATCH_FEE}();
    }

    function _enterPair() internal {
        _hatchKaiju(alice);
        _hatchKaiju(bob);
        vm.prank(alice);
        game.enterClash{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterClash{value: ENTRY_FEE}(2);
    }
}
