// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/GladiatorArena.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract GladiatorArenaHarness is GladiatorArena {
    constructor(
        uint256 _gladiatorMintFee,
        uint256 _entryFee,
        uint256 _boutInterval,
        uint256 _protocolRakeBps,
        uint32 _initialVitality,
        uint32 _minVitality,
        uint256 _maxEntrantsPerBout
    )
        GladiatorArena(
            _gladiatorMintFee,
            _entryFee,
            _boutInterval,
            _protocolRakeBps,
            _initialVitality,
            _minVitality,
            _maxEntrantsPerBout
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract GladiatorArenaTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    GladiatorArenaHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant GLADIATOR_MINT_FEE = 0.01 ether;
    uint256 constant ENTRY_FEE = 0.001 ether;
    uint256 constant BOUT_INTERVAL = 60;
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint32 constant INITIAL_VITALITY = 500;
    uint32 constant MIN_VITALITY = 50;
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

        game = new GladiatorArenaHarness(
            GLADIATOR_MINT_FEE,
            ENTRY_FEE,
            BOUT_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_VITALITY,
            MIN_VITALITY,
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
        assertEq(game.nextGladiatorId(), 1);
        assertEq(game.currentBoutId(), 1);
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.totalBoutsResolved(), 0);
    }

    function test_Immutables() public view {
        assertEq(game.gladiatorMintFee(), GLADIATOR_MINT_FEE);
        assertEq(game.entryFee(), ENTRY_FEE);
        assertEq(game.boutInterval(), BOUT_INTERVAL);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
        assertEq(game.initialVitality(), INITIAL_VITALITY);
        assertEq(game.minVitality(), MIN_VITALITY);
        assertEq(game.maxEntrantsPerBout(), MAX_ENTRANTS);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("GladiatorArena: boutInterval=0");
        new GladiatorArenaHarness(
            GLADIATOR_MINT_FEE, ENTRY_FEE, 0, PROTOCOL_RAKE_BPS,
            INITIAL_VITALITY, MIN_VITALITY, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("GladiatorArena: rake > 20%");
        new GladiatorArenaHarness(
            GLADIATOR_MINT_FEE, ENTRY_FEE, BOUT_INTERVAL, 2001,
            INITIAL_VITALITY, MIN_VITALITY, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsBadVitalityOrdering() public {
        vm.expectRevert("GladiatorArena: vitality ordering");
        new GladiatorArenaHarness(
            GLADIATOR_MINT_FEE, ENTRY_FEE, BOUT_INTERVAL, PROTOCOL_RAKE_BPS,
            50, 500, MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsLowMaxEntrants() public {
        vm.expectRevert("GladiatorArena: maxEntrants < 2");
        new GladiatorArenaHarness(
            GLADIATOR_MINT_FEE, ENTRY_FEE, BOUT_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_VITALITY, MIN_VITALITY, 1
        );
    }

    function test_ConstructorRejectsHighMaxEntrants() public {
        vm.expectRevert("GladiatorArena: maxEntrants > 16");
        new GladiatorArenaHarness(
            GLADIATOR_MINT_FEE, ENTRY_FEE, BOUT_INTERVAL, PROTOCOL_RAKE_BPS,
            INITIAL_VITALITY, MIN_VITALITY, 17
        );
    }

    // ===============================================================
    //  Section 3 — Gladiator minting
    // ===============================================================

    function test_MintGladiator() public {
        vm.prank(alice);
        uint256 id = game.mintGladiator{value: GLADIATOR_MINT_FEE}();
        assertEq(id, 1);
        GladiatorArena.Gladiator memory g = game.getGladiator(1);
        assertEq(g.owner, alice);
        assertEq(g.vitality, INITIAL_VITALITY);
        assertEq(g.victories, 0);
        assertEq(g.bouts, 0);
        assertEq(game.protocolFeeBalance(), GLADIATOR_MINT_FEE);
    }

    function test_MintGladiatorRejectsInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert("GladiatorArena: insufficient mint fee");
        game.mintGladiator{value: GLADIATOR_MINT_FEE - 1}();
    }

    function test_MintGladiatorRefundsOverpayment() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        game.mintGladiator{value: GLADIATOR_MINT_FEE + 1 ether}();
        assertEq(alice.balance, before - GLADIATOR_MINT_FEE);
    }

    function test_MintGladiatorIdsAreSequential() public {
        vm.prank(alice);
        game.mintGladiator{value: GLADIATOR_MINT_FEE}();
        vm.prank(bob);
        game.mintGladiator{value: GLADIATOR_MINT_FEE}();
        vm.prank(carol);
        game.mintGladiator{value: GLADIATOR_MINT_FEE}();

        assertEq(game.nextGladiatorId(), 4);
        assertEq(game.getGladiator(1).owner, alice);
        assertEq(game.getGladiator(2).owner, bob);
        assertEq(game.getGladiator(3).owner, carol);
    }

    // ===============================================================
    //  Section 4 — Bout entry
    // ===============================================================

    function test_EnterBout() public {
        _mintGladiator(alice);
        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE}(1);

        assertEq(game.currentEntrantCount(), 1);
        assertEq(game.currentPrizePool(), ENTRY_FEE);
        assertTrue(game.enteredInCurrentBout(1));
    }

    function test_EnterBoutRejectsNonOwner() public {
        _mintGladiator(alice);
        vm.prank(bob);
        vm.expectRevert("GladiatorArena: not owner");
        game.enterBout{value: ENTRY_FEE}(1);
    }

    function test_EnterBoutRejectsDoubleEntry() public {
        _mintGladiator(alice);
        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE}(1);
        vm.prank(alice);
        vm.expectRevert("GladiatorArena: already entered");
        game.enterBout{value: ENTRY_FEE}(1);
    }

    function test_EnterBoutRejectsInsufficientFee() public {
        _mintGladiator(alice);
        vm.prank(alice);
        vm.expectRevert("GladiatorArena: insufficient entry fee");
        game.enterBout{value: ENTRY_FEE - 1}(1);
    }

    function test_EnterBoutRejectsFull() public {
        for (uint256 i = 0; i < MAX_ENTRANTS; i++) {
            address player = vm.addr(0x1000 + i);
            vm.deal(player, 1 ether);
            vm.prank(player);
            uint256 id = game.mintGladiator{value: GLADIATOR_MINT_FEE}();
            vm.prank(player);
            game.enterBout{value: ENTRY_FEE}(id);
        }

        _mintGladiator(alice);
        uint256 aliceGladiatorId = game.nextGladiatorId() - 1;

        vm.prank(alice);
        vm.expectRevert("GladiatorArena: bout full");
        game.enterBout{value: ENTRY_FEE}(aliceGladiatorId);
    }

    function test_EnterBoutRefundsOverpayment() public {
        _mintGladiator(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE + 1 ether}(1);
        assertEq(alice.balance, before - ENTRY_FEE);
    }

    // ===============================================================
    //  Section 5 — Bout resolution
    // ===============================================================

    function test_ShouldProgressFalseWithOneEntrant() public {
        _mintGladiator(alice);
        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + BOUT_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWithTwoEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ShouldProgressFalseBeforeInterval() public {
        _enterPair();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ResolveBoutIncrementsBoutId() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentBoutId(), 2);
    }

    function test_ResolveBoutDistributesPrize() public {
        _enterPair();
        uint256 poolBefore = game.currentPrizePool();
        assertEq(poolBefore, ENTRY_FEE * 2);

        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        uint256 expectedRake = (poolBefore * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPrize = poolBefore - expectedRake;

        uint256 withdrawable = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        assertEq(withdrawable, expectedPrize);
        assertEq(game.protocolFeeBalance() - GLADIATOR_MINT_FEE * 2, expectedRake);
    }

    function test_ResolveBoutClearsEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertFalse(game.enteredInCurrentBout(1));
        assertFalse(game.enteredInCurrentBout(2));
    }

    function test_ResolveBoutAppliesWounds() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(bytes32(uint256(42)));

        GladiatorArena.Gladiator memory g1 = game.getGladiator(1);
        GladiatorArena.Gladiator memory g2 = game.getGladiator(2);

        assertLt(g1.vitality, INITIAL_VITALITY, "wounds reduce vitality");
        assertLt(g2.vitality, INITIAL_VITALITY, "wounds reduce vitality");
        assertGe(g1.vitality, INITIAL_VITALITY - 20);
        assertGe(g2.vitality, INITIAL_VITALITY - 20);
        assertEq(g1.bouts, 1);
        assertEq(g2.bouts, 1);
    }

    function test_ResolveBoutIncrementsWinnerVictories() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        GladiatorArena.Gladiator memory g1 = game.getGladiator(1);
        GladiatorArena.Gladiator memory g2 = game.getGladiator(2);
        uint256 totalVictories = g1.victories + g2.victories;
        assertEq(totalVictories, 1, "exactly one victor");
    }

    function test_ResolveBoutEmitsEvent() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);

        vm.expectEmit(true, false, false, false, address(game));
        emit GladiatorArena.BoutResolved(1, 0, address(0), 0, 0, bytes32(0));
        game.tickForTest(bytes32(uint256(7)));
    }

    function test_ResolveBoutRejectsTooSoon() public {
        _enterPair();
        vm.expectRevert("GladiatorArena: too soon");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveBoutRejectsStaleLoopID() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        vm.expectRevert("GladiatorArena: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    function test_ResolveBoutRejectsNotEnoughEntrants() public {
        _mintGladiator(alice);
        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + BOUT_INTERVAL);
        vm.expectRevert("GladiatorArena: not enough entrants");
        game.tickForTest(bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 6 — Victory claim (pull-payment)
    // ===============================================================

    function test_ClaimVictory() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        address winner = game.pendingWithdrawals(alice) > 0 ? alice : bob;
        uint256 pending = game.pendingWithdrawals(winner);
        uint256 before = winner.balance;

        vm.prank(winner);
        game.claimVictory();

        assertEq(winner.balance - before, pending);
        assertEq(game.pendingWithdrawals(winner), 0);
    }

    function test_ClaimVictoryRejectsZero() public {
        vm.prank(alice);
        vm.expectRevert("GladiatorArena: nothing to claim");
        game.claimVictory();
    }

    // ===============================================================
    //  Section 7 — Multiple sequential bouts
    // ===============================================================

    function test_MultipleBouts() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 5; i++) {
            ts += BOUT_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("bout", i))))
            );

            if (i < 4) {
                vm.prank(alice);
                game.enterBout{value: ENTRY_FEE}(1);
                vm.prank(bob);
                game.enterBout{value: ENTRY_FEE}(2);
            }
        }

        assertEq(game.totalBoutsResolved(), 5);
        assertEq(game.currentBoutId(), 6);
    }

    function test_WoundsRetireGladiatorAfterManyBouts() public {
        _enterPair();
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 80; i++) {
            ts += BOUT_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("retirement", i))))
            );

            if (game.getGladiator(1).vitality > MIN_VITALITY && i < 79) {
                vm.prank(alice);
                try game.enterBout{value: ENTRY_FEE}(1) {} catch { break; }
                vm.prank(bob);
                try game.enterBout{value: ENTRY_FEE}(2) {} catch { break; }
            } else {
                break;
            }
        }

        GladiatorArena.Gladiator memory g1 = game.getGladiator(1);
        assertLt(g1.vitality, INITIAL_VITALITY, "wounds accrued");
    }

    // ===============================================================
    //  Section 8 — Weighted victor selection
    // ===============================================================

    function test_HigherVitalityMoreLikelyToWin() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        // seed = 100 → weight = 100 → gladiator 1 wins
        game.tickForTest(bytes32(uint256(100)));

        GladiatorArena.Gladiator memory g1 = game.getGladiator(1);
        GladiatorArena.Gladiator memory g2 = game.getGladiator(2);
        assertEq(g1.victories, 1, "gladiator 1 should win with weight 100");
        assertEq(g2.victories, 0);
    }

    function test_Gladiator2WinsWithHighWeight() public {
        _enterPair();
        vm.warp(block.timestamp + BOUT_INTERVAL);
        // seed = 600 → weight = 600 → gladiator 2 wins
        game.tickForTest(bytes32(uint256(600)));

        GladiatorArena.Gladiator memory g1 = game.getGladiator(1);
        GladiatorArena.Gladiator memory g2 = game.getGladiator(2);
        assertEq(g1.victories, 0);
        assertEq(g2.victories, 1);
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _mintGladiator(alice);
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, GLADIATOR_MINT_FEE);
        assertEq(admin.balance - before, GLADIATOR_MINT_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceeds() public {
        vm.expectRevert("GladiatorArena: exceeds balance");
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
        vm.warp(block.timestamp + BOUT_INTERVAL);

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

    function testFuzz_BoutSettlementInvariant(bytes32 randomness) public {
        _enterPair();
        uint256 pool = game.currentPrizePool();
        uint256 feeBefore = game.protocolFeeBalance();

        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(randomness);

        uint256 rake = (pool * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 prize = pool - rake;

        uint256 totalPending = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        uint256 feeDelta = game.protocolFeeBalance() - feeBefore;

        assertEq(totalPending, prize, "prize to one victor");
        assertEq(feeDelta, rake, "fee matches rake");
    }

    function testFuzz_WoundBounds(bytes32 randomness) public {
        _enterPair();
        uint32 vitalityBefore1 = game.getGladiator(1).vitality;
        uint32 vitalityBefore2 = game.getGladiator(2).vitality;

        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(randomness);

        uint32 wound1 = vitalityBefore1 - game.getGladiator(1).vitality;
        uint32 wound2 = vitalityBefore2 - game.getGladiator(2).vitality;

        assertGe(wound1, game.WOUND_MIN());
        assertLe(wound1, game.WOUND_MAX());
        assertGe(wound2, game.WOUND_MIN());
        assertLe(wound2, game.WOUND_MAX());
    }

    function testFuzz_VictorInBounds(bytes32 randomness) public {
        _mintGladiator(alice);
        _mintGladiator(bob);
        _mintGladiator(carol);

        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterBout{value: ENTRY_FEE}(2);
        vm.prank(carol);
        game.enterBout{value: ENTRY_FEE}(3);

        vm.warp(block.timestamp + BOUT_INTERVAL);
        game.tickForTest(randomness);

        uint256 totalVictories = game.getGladiator(1).victories +
            game.getGladiator(2).victories +
            game.getGladiator(3).victories;
        assertEq(totalVictories, 1, "exactly one victor");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _mintGladiator(address who) internal returns (uint256) {
        vm.prank(who);
        return game.mintGladiator{value: GLADIATOR_MINT_FEE}();
    }

    function _enterPair() internal {
        _mintGladiator(alice);
        _mintGladiator(bob);
        vm.prank(alice);
        game.enterBout{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterBout{value: ENTRY_FEE}(2);
    }
}
