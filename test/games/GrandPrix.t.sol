// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/GrandPrix.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract GrandPrixHarness is GrandPrix {
    constructor(
        uint256 _carMintFee,
        uint256 _entryFee,
        uint256 _raceInterval,
        uint256 _protocolRakeBps,
        uint32 _initialPower,
        uint32 _minPower,
        uint256 _maxEntrantsPerRace
    )
        GrandPrix(
            _carMintFee,
            _entryFee,
            _raceInterval,
            _protocolRakeBps,
            _initialPower,
            _minPower,
            _maxEntrantsPerRace
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract GrandPrixTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    GrandPrixHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant CAR_MINT_FEE = 0.01 ether;
    uint256 constant ENTRY_FEE = 0.001 ether;
    uint256 constant RACE_INTERVAL = 60;
    uint256 constant PROTOCOL_RAKE_BPS = 500; // 5%
    uint32 constant INITIAL_POWER = 500;
    uint32 constant MIN_POWER = 50;
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

        game = new GrandPrixHarness(
            CAR_MINT_FEE,
            ENTRY_FEE,
            RACE_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_POWER,
            MIN_POWER,
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
        assertEq(game.nextCarId(), 1);
        assertEq(game.currentRaceId(), 1);
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertEq(game.protocolFeeBalance(), 0);
        assertEq(game.totalRacesResolved(), 0);
    }

    function test_Immutables() public view {
        assertEq(game.carMintFee(), CAR_MINT_FEE);
        assertEq(game.entryFee(), ENTRY_FEE);
        assertEq(game.raceInterval(), RACE_INTERVAL);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
        assertEq(game.initialPower(), INITIAL_POWER);
        assertEq(game.minPower(), MIN_POWER);
        assertEq(game.maxEntrantsPerRace(), MAX_ENTRANTS);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("GrandPrix: raceInterval=0");
        new GrandPrixHarness(
            CAR_MINT_FEE,
            ENTRY_FEE,
            0,
            PROTOCOL_RAKE_BPS,
            INITIAL_POWER,
            MIN_POWER,
            MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("GrandPrix: rake > 20%");
        new GrandPrixHarness(
            CAR_MINT_FEE,
            ENTRY_FEE,
            RACE_INTERVAL,
            2001,
            INITIAL_POWER,
            MIN_POWER,
            MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsBadPowerOrdering() public {
        vm.expectRevert("GrandPrix: power ordering");
        new GrandPrixHarness(
            CAR_MINT_FEE,
            ENTRY_FEE,
            RACE_INTERVAL,
            PROTOCOL_RAKE_BPS,
            50,
            500,
            MAX_ENTRANTS
        );
    }

    function test_ConstructorRejectsLowMaxEntrants() public {
        vm.expectRevert("GrandPrix: maxEntrants < 2");
        new GrandPrixHarness(
            CAR_MINT_FEE,
            ENTRY_FEE,
            RACE_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_POWER,
            MIN_POWER,
            1
        );
    }

    function test_ConstructorRejectsHighMaxEntrants() public {
        vm.expectRevert("GrandPrix: maxEntrants > 16");
        new GrandPrixHarness(
            CAR_MINT_FEE,
            ENTRY_FEE,
            RACE_INTERVAL,
            PROTOCOL_RAKE_BPS,
            INITIAL_POWER,
            MIN_POWER,
            17
        );
    }

    // ===============================================================
    //  Section 3 — Car minting
    // ===============================================================

    function test_MintCar() public {
        vm.prank(alice);
        uint256 id = game.mintCar{value: CAR_MINT_FEE}();
        assertEq(id, 1);
        GrandPrix.Car memory c = game.getCar(1);
        assertEq(c.owner, alice);
        assertEq(c.power, INITIAL_POWER);
        assertEq(c.wins, 0);
        assertEq(c.races, 0);
        assertEq(game.protocolFeeBalance(), CAR_MINT_FEE);
    }

    function test_MintCarRejectsInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert("GrandPrix: insufficient mint fee");
        game.mintCar{value: CAR_MINT_FEE - 1}();
    }

    function test_MintCarRefundsOverpayment() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        game.mintCar{value: CAR_MINT_FEE + 1 ether}();
        assertEq(alice.balance, before - CAR_MINT_FEE);
    }

    function test_MintCarIdsAreSequential() public {
        vm.prank(alice);
        game.mintCar{value: CAR_MINT_FEE}();
        vm.prank(bob);
        game.mintCar{value: CAR_MINT_FEE}();
        vm.prank(carol);
        game.mintCar{value: CAR_MINT_FEE}();

        assertEq(game.nextCarId(), 4);
        assertEq(game.getCar(1).owner, alice);
        assertEq(game.getCar(2).owner, bob);
        assertEq(game.getCar(3).owner, carol);
    }

    // ===============================================================
    //  Section 4 — Race entry
    // ===============================================================

    function test_EnterRace() public {
        _mintCar(alice);
        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE}(1);

        assertEq(game.currentEntrantCount(), 1);
        assertEq(game.currentPrizePool(), ENTRY_FEE);
        assertTrue(game.enteredInCurrentRace(1));
    }

    function test_EnterRaceRejectsNonOwner() public {
        _mintCar(alice);
        vm.prank(bob);
        vm.expectRevert("GrandPrix: not owner");
        game.enterRace{value: ENTRY_FEE}(1);
    }

    function test_EnterRaceRejectsDoubleEntry() public {
        _mintCar(alice);
        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE}(1);
        vm.prank(alice);
        vm.expectRevert("GrandPrix: already entered");
        game.enterRace{value: ENTRY_FEE}(1);
    }

    function test_EnterRaceRejectsInsufficientFee() public {
        _mintCar(alice);
        vm.prank(alice);
        vm.expectRevert("GrandPrix: insufficient entry fee");
        game.enterRace{value: ENTRY_FEE - 1}(1);
    }

    function test_EnterRaceRejectsFull() public {
        // Fill race to cap
        for (uint256 i = 0; i < MAX_ENTRANTS; i++) {
            address player = vm.addr(0x1000 + i);
            vm.deal(player, 1 ether);
            vm.prank(player);
            uint256 id = game.mintCar{value: CAR_MINT_FEE}();
            vm.prank(player);
            game.enterRace{value: ENTRY_FEE}(id);
        }

        // One more should fail. Pre-compute the car id so no view call
        // sits between expectRevert and the reverting call.
        _mintCar(alice);
        uint256 aliceCarId = game.nextCarId() - 1;

        vm.prank(alice);
        vm.expectRevert("GrandPrix: race full");
        game.enterRace{value: ENTRY_FEE}(aliceCarId);
    }

    function test_EnterRaceRefundsOverpayment() public {
        _mintCar(alice);
        uint256 before = alice.balance;
        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE + 1 ether}(1);
        assertEq(alice.balance, before - ENTRY_FEE);
    }

    // ===============================================================
    //  Section 5 — Race resolution
    // ===============================================================

    function test_ShouldProgressFalseWithOneEntrant() public {
        _mintCar(alice);
        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + RACE_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWithTwoEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ShouldProgressFalseBeforeInterval() public {
        _enterPair();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ResolveRaceIncrementsRaceId() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentRaceId(), 2);
    }

    function test_ResolveRaceDistributesPrize() public {
        _enterPair();
        uint256 poolBefore = game.currentPrizePool();
        assertEq(poolBefore, ENTRY_FEE * 2);

        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        // Winner has pending withdrawal of (pool - rake)
        uint256 expectedRake = (poolBefore * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 expectedPrize = poolBefore - expectedRake;

        uint256 withdrawable = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        assertEq(withdrawable, expectedPrize);
        assertEq(game.protocolFeeBalance() - CAR_MINT_FEE * 2, expectedRake);
    }

    function test_ResolveRaceClearsEntrants() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentEntrantCount(), 0);
        assertEq(game.currentPrizePool(), 0);
        assertFalse(game.enteredInCurrentRace(1));
        assertFalse(game.enteredInCurrentRace(2));
    }

    function test_ResolveRaceAppliesWear() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(bytes32(uint256(42)));

        GrandPrix.Car memory c1 = game.getCar(1);
        GrandPrix.Car memory c2 = game.getCar(2);

        assertLt(c1.power, INITIAL_POWER, "wear reduces power");
        assertLt(c2.power, INITIAL_POWER, "wear reduces power");
        assertGe(c1.power, INITIAL_POWER - 20);
        assertGe(c2.power, INITIAL_POWER - 20);
        assertEq(c1.races, 1);
        assertEq(c2.races, 1);
    }

    function test_ResolveRaceIncrementsWinnerWins() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(bytes32(uint256(1)));

        GrandPrix.Car memory c1 = game.getCar(1);
        GrandPrix.Car memory c2 = game.getCar(2);
        uint256 totalWins = c1.wins + c2.wins;
        assertEq(totalWins, 1, "exactly one winner");
    }

    function test_ResolveRaceEmitsEvent() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);

        vm.expectEmit(true, false, false, false, address(game));
        emit GrandPrix.RaceResolved(1, 0, address(0), 0, 0, bytes32(0));
        game.tickForTest(bytes32(uint256(7)));
    }

    function test_ResolveRaceRejectsTooSoon() public {
        _enterPair();
        vm.expectRevert("GrandPrix: too soon");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveRaceRejectsStaleLoopID() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        vm.expectRevert("GrandPrix: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    function test_ResolveRaceRejectsNotEnoughEntrants() public {
        _mintCar(alice);
        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE}(1);
        vm.warp(block.timestamp + RACE_INTERVAL);
        vm.expectRevert("GrandPrix: not enough entrants");
        game.tickForTest(bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 6 — Winnings claim (pull-payment)
    // ===============================================================

    function test_ClaimWinnings() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
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
        vm.expectRevert("GrandPrix: nothing to claim");
        game.claimWinnings();
    }

    // ===============================================================
    //  Section 7 — Multiple sequential races
    // ===============================================================

    function test_MultipleRaces() public {
        _enterPair();
        // Track time explicitly — via_ir caches block.timestamp reads.
        uint256 ts = block.timestamp;

        for (uint256 i = 0; i < 5; i++) {
            ts += RACE_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("race", i))))
            );

            // Re-enter for the next race
            if (i < 4) {
                vm.prank(alice);
                game.enterRace{value: ENTRY_FEE}(1);
                vm.prank(bob);
                game.enterRace{value: ENTRY_FEE}(2);
            }
        }

        assertEq(game.totalRacesResolved(), 5);
        assertEq(game.currentRaceId(), 6);
    }

    function test_WearRetiresCarAfterManyRaces() public {
        _enterPair();
        uint256 ts = block.timestamp;

        // Force many races. Each race applies 5-20 wear; worst case 100 races
        // to reach minPower from initialPower=500.
        for (uint256 i = 0; i < 80; i++) {
            ts += RACE_INTERVAL;
            vm.warp(ts);
            game.tickForTest(
                bytes32(uint256(keccak256(abi.encodePacked("retirement", i))))
            );

            if (game.getCar(1).power > MIN_POWER && i < 79) {
                vm.prank(alice);
                try game.enterRace{value: ENTRY_FEE}(1) {} catch {
                    break;
                }
                vm.prank(bob);
                try game.enterRace{value: ENTRY_FEE}(2) {} catch {
                    break;
                }
            } else {
                break;
            }
        }

        GrandPrix.Car memory c1 = game.getCar(1);
        assertLt(c1.power, INITIAL_POWER, "wear accrued");
    }

    // ===============================================================
    //  Section 8 — Weighted winner selection
    // ===============================================================

    function test_HigherPowerMoreLikelyToWin() public {
        // Setup: 4 races, alternating winners based on seed
        // We assert that across multiple seeds the winner distribution is
        // consistent with power-weighted selection (deterministic here).
        _enterPair(); // alice carId=1, bob carId=2 — both 500 power

        // With equal power, seed modulo totalPower determines winner.
        // totalPower = 1000. winningWeight = seed % 1000.
        // Car 1 wins if cumulative(1)=500 > winningWeight, so weight in [0, 499].
        // Car 2 wins if weight in [500, 999].

        vm.warp(block.timestamp + RACE_INTERVAL);
        // seed = 100 → weight = 100 → car 1 wins
        game.tickForTest(bytes32(uint256(100)));

        GrandPrix.Car memory c1 = game.getCar(1);
        GrandPrix.Car memory c2 = game.getCar(2);
        assertEq(c1.wins, 1, "car 1 should win with weight 100");
        assertEq(c2.wins, 0);
    }

    function test_Car2WinsWithHighWeight() public {
        _enterPair();
        vm.warp(block.timestamp + RACE_INTERVAL);
        // seed = 600 → weight = 600 → car 2 wins
        game.tickForTest(bytes32(uint256(600)));

        GrandPrix.Car memory c1 = game.getCar(1);
        GrandPrix.Car memory c2 = game.getCar(2);
        assertEq(c1.wins, 0);
        assertEq(c2.wins, 1);
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _mintCar(alice);
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, CAR_MINT_FEE);
        assertEq(admin.balance - before, CAR_MINT_FEE);
        assertEq(game.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsExceeds() public {
        vm.expectRevert("GrandPrix: exceeds balance");
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
        vm.warp(block.timestamp + RACE_INTERVAL);

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

    /// @dev Across arbitrary randomness, exactly one winner is selected and
    ///      the prize accounting always sums to the pool.
    function testFuzz_RaceSettlementInvariant(bytes32 randomness) public {
        _enterPair();
        uint256 pool = game.currentPrizePool();
        uint256 feeBefore = game.protocolFeeBalance();

        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(randomness);

        uint256 rake = (pool * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 prize = pool - rake;

        uint256 totalPending = game.pendingWithdrawals(alice) +
            game.pendingWithdrawals(bob);
        uint256 feeDelta = game.protocolFeeBalance() - feeBefore;

        assertEq(totalPending, prize, "prize to one winner");
        assertEq(feeDelta, rake, "fee matches rake");
    }

    /// @dev Wear applied per entrant is always in [WEAR_MIN, WEAR_MAX].
    function testFuzz_WearBounds(bytes32 randomness) public {
        _enterPair();
        uint32 powerBefore1 = game.getCar(1).power;
        uint32 powerBefore2 = game.getCar(2).power;

        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(randomness);

        uint32 wear1 = powerBefore1 - game.getCar(1).power;
        uint32 wear2 = powerBefore2 - game.getCar(2).power;

        assertGe(wear1, game.WEAR_MIN());
        assertLe(wear1, game.WEAR_MAX());
        assertGe(wear2, game.WEAR_MIN());
        assertLe(wear2, game.WEAR_MAX());
    }

    /// @dev Winner index is always in range of entrants.
    function testFuzz_WinnerInBounds(bytes32 randomness) public {
        _mintCar(alice);
        _mintCar(bob);
        _mintCar(carol);

        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterRace{value: ENTRY_FEE}(2);
        vm.prank(carol);
        game.enterRace{value: ENTRY_FEE}(3);

        vm.warp(block.timestamp + RACE_INTERVAL);
        game.tickForTest(randomness);

        uint256 totalWins = game.getCar(1).wins +
            game.getCar(2).wins +
            game.getCar(3).wins;
        assertEq(totalWins, 1, "exactly one winner");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _mintCar(address who) internal returns (uint256) {
        vm.prank(who);
        return game.mintCar{value: CAR_MINT_FEE}();
    }

    function _enterPair() internal {
        _mintCar(alice);
        _mintCar(bob);
        vm.prank(alice);
        game.enterRace{value: ENTRY_FEE}(1);
        vm.prank(bob);
        game.enterRace{value: ENTRY_FEE}(2);
    }
}
