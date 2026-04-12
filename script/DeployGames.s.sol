// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/AutoLoopRegistrar.sol";
import "../src/games/PitRow.sol";
import "../src/games/GrandPrix.sol";
import "../src/games/SponsorAuction.sol";
import "../src/games/PhantomDriver.sol";
import "../src/games/OracleRun.sol";

/**
 * @title DeployGames
 * @notice Deploys the five AutoLoop demo games against an existing
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

        // ---- PitRow (Decay Tower) ----
        PitRow pitRow = new PitRow(
            0.01 ether, // base mint fee
            0.002 ether, // repair fee
            60, // 60s tick interval
            10_000, // maxHealth (100.00%)
            100, // 1%/hour passive decay
            1000, // 10% insurance premium
            5000 // 50% salvage target payout
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(pitRow),
            maxGas
        );

        // ---- GrandPrix (Always-On Race) ----
        GrandPrix grandPrix = new GrandPrix(
            0.01 ether, // car mint fee
            0.001 ether, // entry fee
            60, // 60s race interval
            500, // 5% rake
            500, // initial power
            50, // min power
            8 // max entrants per race
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(grandPrix),
            maxGas
        );

        // ---- SponsorAuction (Rolling Auction) ----
        SponsorAuction sponsorAuction = new SponsorAuction(
            120, // 120s auction duration
            3600, // 1hr sponsorship period
            0.001 ether, // min bid
            500, // 5% min increment
            500, // 5% protocol rake
            slotReceiver
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(sponsorAuction),
            maxGas
        );

        // ---- PhantomDriver (Commit-Reveal MVP Bet) ----
        PhantomDriver phantomDriver = new PhantomDriver(
            120, // 2min commit phase
            120, // 2min reveal phase
            0.001 ether, // min stake
            500 // 5% rake
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(phantomDriver),
            maxGas
        );

        // ---- OracleRun (Autonomous Dungeon) ----
        OracleRun oracleRun = new OracleRun(
            0.01 ether, // character mint fee
            0.002 ether, // entry fee
            60, // 60s expedition interval
            500, // 5% rake
            300, // base difficulty
            50, // difficulty per floor
            400 // initial character power
        );
        registrar.registerAutoLoopFor{value: fundAmount}(
            address(oracleRun),
            maxGas
        );

        vm.stopBroadcast();

        // ---- Console output ----
        console.log("PitRow:         ", address(pitRow));
        console.log("GrandPrix:      ", address(grandPrix));
        console.log("SponsorAuction: ", address(sponsorAuction));
        console.log("PhantomDriver:  ", address(phantomDriver));
        console.log("OracleRun:      ", address(oracleRun));
    }
}
