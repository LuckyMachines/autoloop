// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/AutoLoopRegistrar.sol";
import "../src/agents/ParameterAlerter.sol";
import "../src/agents/SupplyGovernanceModule.sol";
import "../src/agents/NFTRegistry.sol";
import "../src/agents/MatchmakingEngine.sol";
import "../src/agents/BreedingMutationEngine.sol";
import "../src/agents/TournamentBracket.sol";

/**
 * @title DeployNewAgents
 * @notice Deploys the 6 new AutoLoop agent primitives (roadmap batch):
 *           ParameterAlerter, SupplyGovernanceModule, NFTRegistry (Standard)
 *           MatchmakingEngine, BreedingMutationEngine, TournamentBracket (VRF)
 *
 * Required env vars:
 *   PRIVATE_KEY            — deployer private key
 *   REGISTRAR_ADDRESS      — address of the deployed AutoLoopRegistrar
 *
 * Optional:
 *   FUND_AMOUNT            — wei to fund each loop registration (default 0.1 ether)
 *   MAX_GAS                — per-update gas cap (default 2_000_000)
 */
contract DeployNewAgents is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address registrarAddr = vm.envAddress("REGISTRAR_ADDRESS");

        uint256 fundAmount;
        try vm.envUint("FUND_AMOUNT") returns (uint256 v) { fundAmount = v; }
        catch { fundAmount = 0.1 ether; }

        uint256 maxGas;
        try vm.envUint("MAX_GAS") returns (uint256 v) { maxGas = v; }
        catch { maxGas = 2_000_000; }

        AutoLoopRegistrar registrar = AutoLoopRegistrar(registrarAddr);

        vm.startBroadcast(pk);

        // ── ParameterAlerter ───────────────────────────────────────────────────
        ParameterAlerter parameterAlerter = new ParameterAlerter(
            3600  // 1hr snapshot interval
        );
        parameterAlerter.addTrackedParam("dropRate", 1000);    // 10%
        parameterAlerter.addTrackedParam("xpMultiplier", 100); // 1.0x
        registrar.registerAutoLoopFor{value: fundAmount}(address(parameterAlerter), maxGas);

        // ── SupplyGovernanceModule ─────────────────────────────────────────────
        SupplyGovernanceModule supplyGovernance = new SupplyGovernanceModule(
            3600  // 1hr check interval
        );
        supplyGovernance.createItemType("Gold Sword", 1000);
        supplyGovernance.queueSupplyChange(0, 100, "Initial supply", 1800); // 30min timelock
        registrar.registerAutoLoopFor{value: fundAmount}(address(supplyGovernance), maxGas);

        // ── NFTRegistry ────────────────────────────────────────────────────────
        NFTRegistry nftRegistry = new NFTRegistry(deployer); // treasury = deployer for demo
        nftRegistry.createCollection("AutoLoop Genesis", 100, 0.001 ether);
        nftRegistry.scheduleRelease(0, 10, block.timestamp + 120); // release in 2 minutes
        registrar.registerAutoLoopFor{value: fundAmount}(address(nftRegistry), maxGas);

        // ── MatchmakingEngine (VRF) ────────────────────────────────────────────
        MatchmakingEngine matchmakingEngine = new MatchmakingEngine(
            3600  // 1hr match interval
        );
        registrar.registerAutoLoopFor{value: fundAmount}(address(matchmakingEngine), maxGas);

        // ── BreedingMutationEngine (VRF) ───────────────────────────────────────
        BreedingMutationEngine breedingEngine = new BreedingMutationEngine(
            3600,        // 1hr breeding cooldown
            0.001 ether  // breeding fee
        );
        registrar.registerAutoLoopFor{value: fundAmount}(address(breedingEngine), maxGas);

        // ── TournamentBracket (VRF) ────────────────────────────────────────────
        TournamentBracket tournamentBracket = new TournamentBracket(
            3600,         // 1hr round interval
            4,            // 4-player bracket
            0.001 ether   // entry fee
        );
        registrar.registerAutoLoopFor{value: fundAmount}(address(tournamentBracket), maxGas);

        vm.stopBroadcast();

        // ── Console output ─────────────────────────────────────────────────────
        console.log("ParameterAlerter:        ", address(parameterAlerter));
        console.log("SupplyGovernance:        ", address(supplyGovernance));
        console.log("NFTRegistry:             ", address(nftRegistry));
        console.log("MatchmakingEngine:       ", address(matchmakingEngine));
        console.log("BreedingEngine:          ", address(breedingEngine));
        console.log("TournamentBracket:       ", address(tournamentBracket));
    }
}
