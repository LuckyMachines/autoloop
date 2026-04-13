// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/games/CrumbleCore.sol";
import "../../src/games/GladiatorArena.sol";
import "../../src/games/MechBrawl.sol";
import "../../src/games/SorcererDuel.sol";
import "../../src/games/KaijuLeague.sol";
import "../../src/games/VoidHarvester.sol";
import "../../src/games/SponsorAuction.sol";
import "../../src/games/GladiatorOracle.sol";
import "../../src/games/OracleRun.sol";
import "../../src/games/KaijuOracle.sol";
import "../../src/games/ForecasterLeaderboard.sol";

// Local harness copies so the snapshot tests can inject randomness without
// constructing ECVRF proofs. Production deploys use the plain contracts.

contract CrumbleCoreSnap is CrumbleCore {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint16 d, uint16 e, uint256 f, uint256 g
    ) CrumbleCore(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract GladiatorArenaSnap is GladiatorArena {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) GladiatorArena(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract MechBrawlSnap is MechBrawl {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) MechBrawl(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract SorcererDuelSnap is SorcererDuel {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) SorcererDuel(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract KaijuLeagueSnap is KaijuLeague {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) KaijuLeague(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract VoidHarvesterSnap is VoidHarvester {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) VoidHarvester(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract ArenaSnapForOracle is GladiatorArena {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) GladiatorArena(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract LeagueSnapForKaijuOracle is KaijuLeague {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) KaijuLeague(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

contract OracleRunSnap is OracleRun {
    constructor(
        uint256 a, uint256 b, uint256 c, uint256 d,
        uint32 e, uint32 f, uint32 g
    ) OracleRun(a, b, c, d, e, f, g) {}
    function tickForTest(bytes32 r) external { _progressInternal(r, _loopID); }
}

/**
 * @title GameGasSnapshotTest
 * @notice Measures and logs real per-tick gas usage across all nine games.
 *
 *         Run with:
 *             forge test --match-contract GameGasSnapshot -vv
 *
 *         Asserts a hard upper bound of 600k gas per tick (well below the
 *         2,000,000 default cap set at registration) so regressions fail CI.
 *         Actual values are printed via console.log for reference.
 */
contract GameGasSnapshotTest is Test {
    uint256 constant GAS_CEILING = 600_000;

    address public alice;
    address public bob;
    address public carol;

    function setUp() public {
        alice = vm.addr(0xA11CE);
        bob   = vm.addr(0xB0B);
        carol = vm.addr(0xCA201);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(address(this), 1000 ether);
    }

    // ===============================================================
    //  CrumbleCore
    // ===============================================================

    function test_Gas_CrumbleCore_StandardTick() public {
        CrumbleCoreSnap game = new CrumbleCoreSnap(
            0.01 ether, 0.002 ether, 60, 10_000, 100, 1000, 5000
        );
        vm.prank(alice); game.mintFloor{value: 0.01 ether}(false);
        vm.prank(bob);   game.mintFloor{value: 0.011 ether}(false);
        vm.prank(carol); game.mintFloor{value: 0.012 ether}(false);
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(42))); uint256 used = g - gasleft();
        _reportGas("CrumbleCore.tick (3 floors)", used);
        assertLt(used, GAS_CEILING, "CrumbleCore tick exceeds ceiling");
    }

    function test_Gas_CrumbleCore_Mint() public {
        CrumbleCoreSnap game = new CrumbleCoreSnap(0.01 ether, 0.002 ether, 60, 10_000, 100, 1000, 5000);
        vm.prank(alice);
        uint256 g = gasleft(); game.mintFloor{value: 0.01 ether}(false); uint256 used = g - gasleft();
        _reportGas("CrumbleCore.mintFloor (no insurance)", used);
        assertLt(used, GAS_CEILING, "CrumbleCore mint exceeds ceiling");
    }

    // ===============================================================
    //  GladiatorArena
    // ===============================================================

    function test_Gas_GladiatorArena_BoutResolution() public {
        GladiatorArenaSnap game = new GladiatorArenaSnap(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x3000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); uint256 id = game.mintGladiator{value: 0.01 ether}();
            vm.prank(p); game.enterBout{value: 0.001 ether}(id);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(100))); uint256 used = g - gasleft();
        _reportGas("GladiatorArena.tick (4 entrants)", used);
        assertLt(used, GAS_CEILING, "GladiatorArena tick exceeds ceiling");
    }

    function test_Gas_GladiatorArena_BoutResolutionMax() public {
        GladiatorArenaSnap game = new GladiatorArenaSnap(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        for (uint256 i = 0; i < 8; i++) {
            address p = vm.addr(0x4000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); uint256 id = game.mintGladiator{value: 0.01 ether}();
            vm.prank(p); game.enterBout{value: 0.001 ether}(id);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(100))); uint256 used = g - gasleft();
        _reportGas("GladiatorArena.tick (8 entrants, max)", used);
        assertLt(used, GAS_CEILING, "GladiatorArena tick at max exceeds ceiling");
    }

    // ===============================================================
    //  MechBrawl
    // ===============================================================

    function test_Gas_MechBrawl_BrawlResolution() public {
        MechBrawlSnap game = new MechBrawlSnap(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x5000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); uint256 id = game.deployMech{value: 0.01 ether}();
            vm.prank(p); game.joinBrawl{value: 0.001 ether}(id);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(100))); uint256 used = g - gasleft();
        _reportGas("MechBrawl.tick (4 entrants)", used);
        assertLt(used, GAS_CEILING, "MechBrawl tick exceeds ceiling");
    }

    // ===============================================================
    //  SorcererDuel
    // ===============================================================

    function test_Gas_SorcererDuel_DuelResolution() public {
        SorcererDuelSnap game = new SorcererDuelSnap(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x6000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); uint256 id = game.summonSorcerer{value: 0.01 ether}();
            vm.prank(p); game.enterDuel{value: 0.001 ether}(id);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(100))); uint256 used = g - gasleft();
        _reportGas("SorcererDuel.tick (4 entrants)", used);
        assertLt(used, GAS_CEILING, "SorcererDuel tick exceeds ceiling");
    }

    // ===============================================================
    //  KaijuLeague
    // ===============================================================

    function test_Gas_KaijuLeague_ClashResolution() public {
        KaijuLeagueSnap game = new KaijuLeagueSnap(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x7000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); uint256 id = game.hatchKaiju{value: 0.01 ether}();
            vm.prank(p); game.enterClash{value: 0.001 ether}(id);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(100))); uint256 used = g - gasleft();
        _reportGas("KaijuLeague.tick (4 entrants)", used);
        assertLt(used, GAS_CEILING, "KaijuLeague tick exceeds ceiling");
    }

    // ===============================================================
    //  VoidHarvester
    // ===============================================================

    function test_Gas_VoidHarvester_MissionResolution() public {
        VoidHarvesterSnap game = new VoidHarvesterSnap(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x8000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); uint256 id = game.deployProbe{value: 0.01 ether}();
            vm.prank(p); game.launchMission{value: 0.001 ether}(id);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(100))); uint256 used = g - gasleft();
        _reportGas("VoidHarvester.tick (4 entrants)", used);
        assertLt(used, GAS_CEILING, "VoidHarvester tick exceeds ceiling");
    }

    // ===============================================================
    //  SponsorAuction
    // ===============================================================

    function test_Gas_SponsorAuction_Close() public {
        SponsorAuction game = new SponsorAuction(
            120, 3600, 0.001 ether, 500, 500, alice
        );
        vm.prank(bob); game.bid{value: 0.001 ether}();
        vm.warp(game.auctionClosesAt());
        bytes memory data = abi.encode(game.currentAuctionId());
        uint256 g = gasleft(); game.progressLoop(data); uint256 used = g - gasleft();
        _reportGas("SponsorAuction.close (with bid)", used);
        assertLt(used, GAS_CEILING, "SponsorAuction close exceeds ceiling");
    }

    function test_Gas_SponsorAuction_CloseNoBids() public {
        SponsorAuction game = new SponsorAuction(120, 3600, 0.001 ether, 500, 500, alice);
        vm.warp(game.auctionClosesAt());
        bytes memory data = abi.encode(game.currentAuctionId());
        uint256 g = gasleft(); game.progressLoop(data); uint256 used = g - gasleft();
        _reportGas("SponsorAuction.close (no bids)", used);
        assertLt(used, GAS_CEILING);
    }

    // ===============================================================
    //  GladiatorOracle
    // ===============================================================

    function test_Gas_GladiatorOracle_Settlement() public {
        ArenaSnapForOracle snap = new ArenaSnapForOracle(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        GladiatorOracle game = new GladiatorOracle(
            address(snap), 120, 120, 0.001 ether, 500
        );

        // Three oracle players commit predictions
        address[3] memory players = [alice, bob, carol];
        uint256[3] memory gids = [uint256(1), uint256(2), uint256(1)]; // alice+carol pick g1, bob picks g2
        bytes32[3] memory salts = [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))];
        for (uint256 i = 0; i < 3; i++) {
            bytes32 c = keccak256(abi.encode(gids[i], salts[i], players[i]));
            vm.prank(players[i]); game.commit{value: 0.001 ether}(c);
        }

        // Mint + enter two arena gladiators
        address p1 = vm.addr(0xF001);
        address p2 = vm.addr(0xF002);
        vm.deal(p1, 1 ether); vm.deal(p2, 1 ether);
        vm.prank(p1); snap.mintGladiator{value: 0.01 ether}(); // g1
        vm.prank(p2); snap.mintGladiator{value: 0.01 ether}(); // g2
        vm.prank(p1); snap.enterBout{value: 0.001 ether}(1);
        vm.prank(p2); snap.enterBout{value: 0.001 ether}(2);

        // Warp past commit phase, have players reveal
        GladiatorOracle.Round memory r = game.getRound(1);
        vm.warp(r.commitEndAt);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(players[i]); game.reveal(gids[i], salts[i]);
        }

        // Warp past both deadlines, resolve arena, then measure oracle settlement gas
        uint256 t = r.revealEndAt > snap.lastBoutAt() + 60 ? r.revealEndAt : snap.lastBoutAt() + 60;
        vm.warp(t);
        snap.tickForTest(bytes32(uint256(0))); // g1 wins

        bytes memory data = abi.encode(uint256(1));
        uint256 g = gasleft(); game.progressLoop(data); uint256 used = g - gasleft();
        _reportGas("GladiatorOracle.settle (3 players, g1 wins)", used);
        assertLt(used, GAS_CEILING, "GladiatorOracle settle exceeds ceiling");
    }

    // ===============================================================
    //  OracleRun
    // ===============================================================

    function test_Gas_OracleRun_Expedition() public {
        OracleRunSnap game = new OracleRunSnap(
            0.01 ether, 0.002 ether, 60, 500, 300, 50, 400
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0x9000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); game.mintCharacter{value: 0.01 ether}();
            vm.prank(p); game.registerForExpedition{value: 0.002 ether}(i + 1);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(type(uint256).max))); uint256 used = g - gasleft();
        _reportGas("OracleRun.tick (4 entrants, all survive)", used);
        assertLt(used, GAS_CEILING, "OracleRun tick exceeds ceiling");
    }

    function test_Gas_OracleRun_Wipe() public {
        OracleRunSnap game = new OracleRunSnap(
            0.01 ether, 0.002 ether, 60, 500, 900, 50, 100
        );
        for (uint256 i = 0; i < 4; i++) {
            address p = vm.addr(0xA000 + i);
            vm.deal(p, 1 ether);
            vm.prank(p); game.mintCharacter{value: 0.01 ether}();
            vm.prank(p); game.registerForExpedition{value: 0.002 ether}(i + 1);
        }
        vm.warp(block.timestamp + 60);
        uint256 g = gasleft(); game.tickForTest(bytes32(uint256(0))); uint256 used = g - gasleft();
        _reportGas("OracleRun.tick (4 entrants, wipe)", used);
        assertLt(used, GAS_CEILING);
    }

    // ===============================================================
    //  KaijuOracle
    // ===============================================================

    function test_Gas_KaijuOracle_Settlement() public {
        LeagueSnapForKaijuOracle snap = new LeagueSnapForKaijuOracle(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        KaijuOracle game = new KaijuOracle(
            address(snap), 120, 120, 0.001 ether, 500
        );

        address[3] memory players = [alice, bob, carol];
        uint256[3] memory kids = [uint256(1), uint256(2), uint256(1)];
        bytes32[3] memory salts = [bytes32(uint256(1)), bytes32(uint256(2)), bytes32(uint256(3))];
        for (uint256 i = 0; i < 3; i++) {
            bytes32 c = keccak256(abi.encode(kids[i], salts[i], players[i]));
            vm.prank(players[i]); game.commit{value: 0.001 ether}(c);
        }

        // Mint and enter two kaijus
        address p1 = vm.addr(0xF101); address p2 = vm.addr(0xF102);
        vm.deal(p1, 1 ether); vm.deal(p2, 1 ether);
        vm.prank(p1); snap.hatchKaiju{value: 0.01 ether}(); // k1
        vm.prank(p2); snap.hatchKaiju{value: 0.01 ether}(); // k2
        vm.prank(p1); snap.enterClash{value: 0.001 ether}(1);
        vm.prank(p2); snap.enterClash{value: 0.001 ether}(2);

        KaijuOracle.Round memory r = game.getRound(1);
        vm.warp(r.commitEndAt);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(players[i]); game.reveal(kids[i], salts[i]);
        }

        uint256 t = r.revealEndAt > snap.lastClashAt() + 60 ? r.revealEndAt : snap.lastClashAt() + 60;
        vm.warp(t);
        snap.tickForTest(bytes32(uint256(0))); // k1 wins

        bytes memory data = abi.encode(uint256(1));
        uint256 g = gasleft(); game.progressLoop(data); uint256 used = g - gasleft();
        _reportGas("KaijuOracle.settle (3 players, k1 wins)", used);
        assertLt(used, GAS_CEILING, "KaijuOracle settle exceeds ceiling");
    }

    // ===============================================================
    //  ForecasterLeaderboard
    // ===============================================================

    function test_Gas_ForecasterLeaderboard_Distribution() public {
        LeagueSnapForKaijuOracle snap = new LeagueSnapForKaijuOracle(
            0.01 ether, 0.001 ether, 60, 500, 500, 50, 8
        );
        KaijuOracle oracleGame = new KaijuOracle(
            address(snap), 60, 60, 0.001 ether, 500
        );
        ForecasterLeaderboard board = new ForecasterLeaderboard(
            address(oracleGame), 3600, 3, 20, 500
        );

        // Fund the prize pool
        board.fundPrizePool{value: 1 ether}();

        // Three forecasters commit and reveal
        address[3] memory players = [alice, bob, carol];
        uint256[3] memory kids = [uint256(1), uint256(1), uint256(2)];
        bytes32[3] memory salts = [bytes32(uint256(10)), bytes32(uint256(11)), bytes32(uint256(12))];
        for (uint256 i = 0; i < 3; i++) {
            bytes32 c = keccak256(abi.encode(kids[i], salts[i], players[i]));
            vm.prank(players[i]); oracleGame.commit{value: 0.001 ether}(c);
        }

        address lp1 = vm.addr(0xF201); address lp2 = vm.addr(0xF202);
        vm.deal(lp1, 1 ether); vm.deal(lp2, 1 ether);
        vm.prank(lp1); snap.hatchKaiju{value: 0.01 ether}();
        vm.prank(lp2); snap.hatchKaiju{value: 0.01 ether}();
        vm.prank(lp1); snap.enterClash{value: 0.001 ether}(1);
        vm.prank(lp2); snap.enterClash{value: 0.001 ether}(2);

        KaijuOracle.Round memory r = oracleGame.getRound(1);
        vm.warp(r.commitEndAt);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(players[i]); oracleGame.reveal(kids[i], salts[i]);
        }

        uint256 t = r.revealEndAt > snap.lastClashAt() + 60 ? r.revealEndAt : snap.lastClashAt() + 60;
        vm.warp(t);
        snap.tickForTest(bytes32(uint256(0)));                 // k1 wins
        oracleGame.progressLoop(abi.encode(uint256(1)));       // oracle settles round 1

        // Warp to distribution time
        vm.warp(board.nextDistributionAt());
        bytes memory data = abi.encode(uint256(1));
        uint256 g = gasleft(); board.progressLoop(data); uint256 used = g - gasleft();
        _reportGas("ForecasterLeaderboard.distribution (3 forecasters, 1 round)", used);
        assertLt(used, GAS_CEILING, "ForecasterLeaderboard distribution exceeds ceiling");
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _reportGas(string memory label, uint256 gasUsed) internal pure {
        console.log("    gas_snapshot:", label, "=>", gasUsed);
    }
}
