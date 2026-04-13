// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/AutoLoopRegistrar.sol";
import "../src/games/CrumbleCore.sol";
import "../src/games/GladiatorArena.sol";
import "../src/games/MechBrawl.sol";
import "../src/games/SorcererDuel.sol";
import "../src/games/KaijuLeague.sol";
import "../src/games/VoidHarvester.sol";
import "../src/games/SponsorAuction.sol";
import "../src/games/GladiatorOracle.sol";
import "../src/games/OracleRun.sol";
import "../src/games/KaijuOracle.sol";
import "../src/games/ForecasterLeaderboard.sol";

/**
 * @title DeployGames
 * @notice Deploys the nine AutoLoop demo games against an existing
 *         AutoLoop / Registry / Registrar deployment, registers each,
 *         and optionally funds them.
 *
 * Required env vars:
 *   PRIVATE_KEY            — deployer private key
 *   REGISTRAR_ADDRESS      — address of the deployed AutoLoopRegistrar
 *   SLOT_RECEIVER          — payout address for SponsorAuction slot
 *
 * Optional env vars:
 *   FUND_AMOUNT            — wei to fund each game with (default 0.1 ether)
 *   MAX_GAS                — per-update gas cap at registration (default 2_000_000)
 *
 * Deploys 11 contracts:
 *   9 original games + KaijuOracle + ForecasterLeaderboard
 *   (KaijuLeague → KaijuOracle → ForecasterLeaderboard is the 3-contract chain)
 */
contract DeployGames is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registrarAddr = vm.envAddress("REGISTRAR_ADDRESS");
        address slotReceiver = vm.envAddress("SLOT_RECEIVER");

        uint256 fundAmount;
        try vm.envUint("FUND_AMOUNT") returns (uint256 v) {
            fundAmount = v;
        } catch {
            fundAmount = 0.1 ether;
        }

        uint256 maxGas;
        try vm.envUint("MAX_GAS") returns (uint256 v) {
            maxGas = v;
        } catch {
            maxGas = 2_000_000;
        }

        AutoLoopRegistrar registrar = AutoLoopRegistrar(registrarAddr);

        vm.startBroadcast(pk);

        // ---- CrumbleCore (Decay Tower) ----
        CrumbleCore crumbleCore = new CrumbleCore(
            0.01 ether,  // base mint fee
            0.002 ether, // repair fee
            60,          // 60s tick interval
            10_000,      // maxHealth (100.00%)
            100,         // 1%/hour passive decay
            1000,        // 10% insurance premium
            5000         // 50% salvage target payout
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(crumbleCore),
            maxGas
        );

        // ---- GladiatorArena (Always-On Colosseum) ----
        GladiatorArena gladiatorArena = new GladiatorArena(
            0.01 ether,  // gladiator mint fee
            0.001 ether, // entry fee
            60,          // 60s bout interval
            500,         // 5% protocol rake
            500,         // initial vitality
            50,          // min vitality
            8            // max entrants per bout
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(gladiatorArena),
            maxGas
        );

        // ---- MechBrawl (Iron Pit) ----
        MechBrawl mechBrawl = new MechBrawl(
            0.01 ether,  // deploy fee
            0.001 ether, // entry fee
            60,          // 60s brawl interval
            500,         // 5% protocol rake
            500,         // initial armor
            50,          // min armor
            8            // max entrants per brawl
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(mechBrawl),
            maxGas
        );

        // ---- SorcererDuel (Arcane Circle) ----
        SorcererDuel sorcererDuel = new SorcererDuel(
            0.01 ether,  // summon fee
            0.001 ether, // entry fee
            60,          // 60s duel interval
            500,         // 5% protocol rake
            500,         // initial mana
            50,          // min mana
            8            // max duelists
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(sorcererDuel),
            maxGas
        );

        // ---- KaijuLeague (Monster League) ----
        KaijuLeague kaijuLeague = new KaijuLeague(
            0.01 ether,  // hatch fee
            0.001 ether, // entry fee
            60,          // 60s clash interval
            500,         // 5% protocol rake
            500,         // initial health
            50,          // min health
            8            // max entrants per clash
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(kaijuLeague),
            maxGas
        );

        // ---- VoidHarvester (Deep Anomaly) ----
        VoidHarvester voidHarvester = new VoidHarvester(
            0.01 ether,  // probe fee
            0.001 ether, // mission fee (entry fee)
            60,          // 60s mission interval
            500,         // 5% protocol rake
            500,         // initial integrity
            50,          // min integrity
            8            // max probes per mission
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(voidHarvester),
            maxGas
        );

        // ---- SponsorAuction (Rolling Auction) ----
        SponsorAuction sponsorAuction = new SponsorAuction(
            120,         // 120s auction duration
            3600,        // 1hr sponsorship period
            0.001 ether, // min bid
            500,         // 5% min increment
            500,         // 5% protocol rake
            slotReceiver
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(sponsorAuction),
            maxGas
        );

        // ---- GladiatorOracle (Bout Prediction Market) ----
        GladiatorOracle gladiatorOracle = new GladiatorOracle(
            address(gladiatorArena), // reads bout results from GladiatorArena
            120,         // 2min commit phase
            120,         // 2min reveal phase
            0.001 ether, // min stake
            500          // 5% rake
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(gladiatorOracle),
            maxGas
        );

        // ---- OracleRun (Autonomous Dungeon) ----
        OracleRun oracleRun = new OracleRun(
            0.01 ether,  // character mint fee
            0.002 ether, // entry fee
            60,          // 60s expedition interval
            500,         // 5% rake
            300,         // base difficulty
            50,          // difficulty per floor
            400          // initial character power
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(oracleRun),
            maxGas
        );

        // ---- KaijuOracle (Clash Prediction Market) ----
        KaijuOracle kaijuOracle = new KaijuOracle(
            address(kaijuLeague), // reads clash results from KaijuLeague
            120,         // 2min commit phase
            120,         // 2min reveal phase
            0.001 ether, // min stake
            500          // 5% rake
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(kaijuOracle),
            maxGas
        );

        // ---- ForecasterLeaderboard (3rd-hop accuracy tracker) ----
        ForecasterLeaderboard forecasterLeaderboard = new ForecasterLeaderboard(
            address(kaijuOracle), // reads settled rounds from KaijuOracle
            3600,        // 1hr distribution interval (testnet; use 604800 for mainnet)
            3,           // top 3 forecasters share the prize pool
            50,          // process up to 50 oracle rounds per tick
            500          // 5% protocol rake on prize pool
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(forecasterLeaderboard),
            maxGas
        );

        vm.stopBroadcast();

        // ---- Console output ----
        console.log("CrumbleCore:             ", address(crumbleCore));
        console.log("GladiatorArena:          ", address(gladiatorArena));
        console.log("MechBrawl:               ", address(mechBrawl));
        console.log("SorcererDuel:            ", address(sorcererDuel));
        console.log("KaijuLeague:             ", address(kaijuLeague));
        console.log("VoidHarvester:           ", address(voidHarvester));
        console.log("SponsorAuction:          ", address(sponsorAuction));
        console.log("GladiatorOracle:         ", address(gladiatorOracle));
        console.log("OracleRun:               ", address(oracleRun));
        console.log("KaijuOracle:             ", address(kaijuOracle));
        console.log("ForecasterLeaderboard:   ", address(forecasterLeaderboard));
    }
}
