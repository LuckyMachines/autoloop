// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/games/PitRow.sol";
import "../../src/games/GrandPrix.sol";
import "../../src/games/SponsorAuction.sol";
import "../../src/games/PhantomDriver.sol";
import "../../src/games/OracleRun.sol";

// Local harness copies so the snapshot tests can inject randomness without
// constructing ECVRF proofs. Production deploys use the plain contracts.

contract PitRowSnap is PitRow {
    constructor(
        uint256 a,
        uint256 b,
        uint256 c,
        uint16 d,
        uint16 e,
        uint256 f,
        uint256 g
    ) PitRow(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external {
        _progressInternal(r, _loopID);
    }
}

contract GrandPrixSnap is GrandPrix {
    constructor(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint32 e,
        uint32 f,
        uint256 g
    ) GrandPrix(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external {
        _progressInternal(r, _loopID);
    }
}

contract PhantomDriverSnap is PhantomDriver {
    constructor(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) PhantomDriver(a, b, c, d) {}
    function tickForTest(bytes32 r) external {
        _progressInternal(r, _loopID);
    }
}

contract OracleRunSnap is OracleRun {
    constructor(
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint32 e,
        uint32 f,
        uint32 g
    ) OracleRun(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external {
        _progressInternal(r, _loopID);
    }
}

/**
 * @title GameGasSnapshotTest
 * @notice Measures and logs real per-tick gas usage across all five games.
 *
 *         Run with:
 *             forge test --match-contract GameGasSnapshot -vv
 *
 *         Asserts a hard upper bound of 600k gas per tick (well below the
 *         2,000,000 default cap set at registration) so regressions fail
 *         CI. Actual values are printed via console.log for reference.
 *
 *         This answers flag 4 from the ESP rebuttal build: gas profile
 *         is observable and regression-detectable.
 */
contract GameGasSnapshotTest is Test {
    uint256 constant GAS_CEILING = 600_000;

    address public alice;
    address public bob;
    address public carol;

    function setUp() public {
        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        carol = vm.addr(0xCA201);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(address(this), 1000 ether);
    }

    // ===============================================================
    //  PitRow
    // ===============================================================

    function test_Gas_PitRow_StandardTick() public {
        PitRowSnap game = new PitRowSnap(
            0.01 ether, // baseMintFee
            0.002 ether, // repairFee
            60, // tickInterval
            10_000, // maxHealth
            100, // passiveDecayPerHour
            1000, // insurancePremiumBps
            5000 // salvageTargetBps
        );

        vm.prank(alice);
        game.mintFloor{value: 0.01 ether}(false);
        vm.prank(bob);
        game.mintFloor{value: 0.011 ether}(false);
        vm.prank(carol);
        game.mintFloor{value: 0.012 ether}(false);

        vm.warp(block.timestamp + 60);

        uint256 gasBefore = gasleft();
        game.tickForTest(bytes32(uint256(42)));
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("PitRow.tick (3 floors)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "PitRow tick exceeds ceiling");
    }

    function test_Gas_PitRow_Mint() public {
        PitRowSnap game = new PitRowSnap(
            0.01 ether,
            0.002 ether,
            60,
            10_000,
            100,
            1000,
            5000
        );

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        game.mintFloor{value: 0.01 ether}(false);
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("PitRow.mintFloor (no insurance)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "PitRow mint exceeds ceiling");
    }

    // ===============================================================
    //  GrandPrix
    // ===============================================================

    function test_Gas_GrandPrix_RaceResolution() public {
        GrandPrixSnap game = new GrandPrixSnap(
            0.01 ether, // carMintFee
            0.001 ether, // entryFee
            60, // raceInterval
            500, // 5% rake
            500, // initialPower
            50, // minPower
            8 // maxEntrants
        );

        // Mint and enter 4 cars
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x3000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p);
            uint256 id = game.mintCar{value: 0.01 ether}();
            vm.prank(p);
            game.enterRace{value: 0.001 ether}(id);
        }

        vm.warp(block.timestamp + 60);

        uint256 gasBefore = gasleft();
        game.tickForTest(bytes32(uint256(100)));
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("GrandPrix.tick (4 entrants)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "GrandPrix tick exceeds ceiling");
    }

    function test_Gas_GrandPrix_RaceResolutionMax() public {
        GrandPrixSnap game = new GrandPrixSnap(
            0.01 ether,
            0.001 ether,
            60,
            500,
            500,
            50,
            8
        );
        for (uint256 i = 0; i < 8; i++) {
            address p = vm.addr(0x4000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p);
            uint256 id = game.mintCar{value: 0.01 ether}();
            vm.prank(p);
            game.enterRace{value: 0.001 ether}(id);
        }

        vm.warp(block.timestamp + 60);

        uint256 gasBefore = gasleft();
        game.tickForTest(bytes32(uint256(100)));
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("GrandPrix.tick (8 entrants, max)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "GrandPrix tick at max exceeds ceiling");
    }

    // ===============================================================
    //  SponsorAuction
    // ===============================================================

    function test_Gas_SponsorAuction_Close() public {
        SponsorAuction game = new SponsorAuction(
            120, // auctionDuration
            3600, // sponsorshipPeriod
            0.001 ether, // minBid
            500, // 5% minIncrementBps
            500, // 5% protocolRakeBps
            alice
        );

        // Place a bid so close has something to settle
        vm.prank(bob);
        game.bid{value: 0.001 ether}();

        vm.warp(game.auctionClosesAt());

        bytes memory data = abi.encode(game.currentAuctionId());
        uint256 gasBefore = gasleft();
        game.progressLoop(data);
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("SponsorAuction.close (with bid)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "SponsorAuction close exceeds ceiling");
    }

    function test_Gas_SponsorAuction_CloseNoBids() public {
        SponsorAuction game = new SponsorAuction(
            120,
            3600,
            0.001 ether,
            500,
            500,
            alice
        );
        vm.warp(game.auctionClosesAt());

        bytes memory data = abi.encode(game.currentAuctionId());
        uint256 gasBefore = gasleft();
        game.progressLoop(data);
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("SponsorAuction.close (no bids)", gasUsed);
        assertLt(gasUsed, GAS_CEILING);
    }

    // ===============================================================
    //  PhantomDriver
    // ===============================================================

    function test_Gas_PhantomDriver_Resolution() public {
        PhantomDriverSnap game = new PhantomDriverSnap(
            120, // commitDuration
            120, // revealDuration
            0.001 ether, // minStake
            500 // 5% rake
        );

        // 3 players commit + reveal
        address[3] memory players = [alice, bob, carol];
        uint8[3] memory roles = [uint8(0), uint8(1), uint8(2)];
        bytes32[3] memory salts = [
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            bytes32(uint256(3))
        ];

        for (uint256 i = 0; i < 3; i++) {
            bytes32 c = keccak256(abi.encode(roles[i], salts[i], players[i]));
            vm.prank(players[i]);
            game.commit{value: 0.001 ether}(c);
        }

        PhantomDriver.Round memory r = game.getRound(1);
        vm.warp(r.commitEndAt);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(players[i]);
            game.reveal(roles[i], salts[i]);
        }

        vm.warp(r.revealEndAt);

        uint256 gasBefore = gasleft();
        game.tickForTest(bytes32(uint256(1)));
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("PhantomDriver.tick (3 players, committed+revealed)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "PhantomDriver tick exceeds ceiling");
    }

    // ===============================================================
    //  OracleRun
    // ===============================================================

    function test_Gas_OracleRun_Expedition() public {
        OracleRunSnap game = new OracleRunSnap(
            0.01 ether, // characterMintFee
            0.002 ether, // entryFee
            60, // interval
            500, // 5% rake
            300, // baseDifficulty
            50, // difficultyPerFloor
            400 // initialPower
        );

        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x5000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p);
            game.mintCharacter{value: 0.01 ether}();
            vm.prank(p);
            game.registerForExpedition{value: 0.002 ether}(i + 1);
        }

        vm.warp(block.timestamp + 60);

        uint256 gasBefore = gasleft();
        game.tickForTest(bytes32(uint256(type(uint256).max)));
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("OracleRun.tick (4 entrants, all survive)", gasUsed);
        assertLt(gasUsed, GAS_CEILING, "OracleRun tick exceeds ceiling");
    }

    function test_Gas_OracleRun_Wipe() public {
        // All characters die on a high-difficulty floor
        OracleRunSnap game = new OracleRunSnap(
            0.01 ether,
            0.002 ether,
            60,
            500,
            900, // baseDifficulty high enough to kill with initialPower=100
            50,
            100
        );

        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x6000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p);
            game.mintCharacter{value: 0.01 ether}();
            vm.prank(p);
            game.registerForExpedition{value: 0.002 ether}(i + 1);
        }

        vm.warp(block.timestamp + 60);

        // Zero randomness guarantees every character rolls 0 → dies
        uint256 gasBefore = gasleft();
        game.tickForTest(bytes32(uint256(0)));
        uint256 gasUsed = gasBefore - gasleft();

        _reportGas("OracleRun.tick (4 entrants, wipe)", gasUsed);
        assertLt(gasUsed, GAS_CEILING);
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _reportGas(string memory label, uint256 gasUsed) internal pure {
        console.log("    gas_snapshot:", label, "=>", gasUsed);
    }
}
