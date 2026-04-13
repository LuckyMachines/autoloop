// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/AutoLoopRegistrar.sol";
import "../src/agents/VaultDeadSwitch.sol";
import "../src/agents/YieldHarvester.sol";
import "../src/agents/AIAgentLoop.sol";
import "../src/agents/DAOExecutor.sol";
import "../src/agents/TreasuryRebalancer.sol";
import "../src/agents/AirdropDistributor.sol";
import "../src/agents/NFTReveal.sol";
import "../src/agents/LotterySweepstakes.sol";

/**
 * @title DeployAgents
 * @notice Deploys the 8 AutoLoop agent demos against an existing
 *         AutoLoop / Registry / Registrar deployment, registers each,
 *         and optionally funds them.
 *
 * Required env vars:
 *   PRIVATE_KEY            — deployer private key
 *   REGISTRAR_ADDRESS      — address of the deployed AutoLoopRegistrar
 *
 * Optional env vars:
 *   FUND_AMOUNT            — wei to fund each agent's loop registration (default 0.1 ether)
 *   MAX_GAS                — per-update gas cap at registration (default 2_000_000)
 *   TOKEN1_ADDRESS         — address of token1 for TreasuryRebalancer
 *                            (default: Sepolia WETH 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9)
 *
 * Deploys 8 agent contracts + 1 MockVault helper (for YieldHarvester):
 *   5 AutoLoopCompatible + 3 AutoLoopVRFCompatible
 */
contract DeployAgents is Script {
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

        address token1Addr;
        try vm.envAddress("TOKEN1_ADDRESS") returns (address v) { token1Addr = v; }
        catch { token1Addr = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; } // Sepolia WETH

        AutoLoopRegistrar registrar = AutoLoopRegistrar(registrarAddr);

        vm.startBroadcast(pk);

        // ── VaultDeadSwitch ────────────────────────────────────────────────────
        // Owner = deployer; beneficiary = deployer (demo). Fund with ETH so the
        // trigger payout is observable.
        VaultDeadSwitch vaultDeadSwitch = new VaultDeadSwitch(
            deployer,   // owner (must check in periodically)
            deployer,   // beneficiary — change to another address for real use
            86400       // 1-day check-in interval (testnet)
        );
        (bool _ok1,) = address(vaultDeadSwitch).call{value: 0.01 ether}("");
        require(_ok1, "VaultDeadSwitch fund failed");
        registrar.registerAutoLoopFor{value: fundAmount}(address(vaultDeadSwitch), maxGas);

        // ── YieldHarvester + MockVault ─────────────────────────────────────────
        // Two-step because MockVault needs the harvester address and vice versa:
        //   1. Deploy YieldHarvester with deployer as temp vault (non-zero placeholder)
        //   2. Deploy MockVault pointing to the real YieldHarvester
        //   3. Fund MockVault with ETH + accrue yield
        //   4. Update YieldHarvester's vault to point at MockVault
        YieldHarvester yieldHarvester = new YieldHarvester(
            deployer,  // temp vault — overwritten in step 4
            300,       // 5-min harvest interval (testnet)
            0          // no minimum yield threshold
        );
        MockVault mockVault = new MockVault(address(yieldHarvester));
        (bool _ok2,) = address(mockVault).call{value: 0.05 ether}("");
        require(_ok2, "MockVault fund failed");
        mockVault.accrueYield(0.04 ether); // set pendingYield so first harvest fires
        yieldHarvester.setVault(address(mockVault));
        registrar.registerAutoLoopFor{value: fundAmount}(address(yieldHarvester), maxGas);

        // ── AIAgentLoop ────────────────────────────────────────────────────────
        AIAgentLoop aiAgentLoop = new AIAgentLoop(
            3600,       // 1hr tick interval
            bytes32(0), // empty instruction hash (update via setInstructionHash post-deploy)
            0           // unlimited ticks
        );
        registrar.registerAutoLoopFor{value: fundAmount}(address(aiAgentLoop), maxGas);

        // ── DAOExecutor ────────────────────────────────────────────────────────
        DAOExecutor daoExecutor = new DAOExecutor(
            3600  // 1hr check interval
        );
        registrar.registerAutoLoopFor{value: fundAmount}(address(daoExecutor), maxGas);

        // ── TreasuryRebalancer ─────────────────────────────────────────────────
        // Fund with ETH so current allocation is 100% token0, drift > threshold.
        TreasuryRebalancer treasuryRebalancer = new TreasuryRebalancer(
            address(0),  // token0: ETH (address(0))
            6000,        // target: 60% ETH
            token1Addr,  // token1: WETH or any ERC20
            500,         // 5% drift threshold
            86400        // 1-day check interval
        );
        (bool _ok3,) = address(treasuryRebalancer).call{value: 0.1 ether}("");
        require(_ok3, "TreasuryRebalancer fund failed");
        registrar.registerAutoLoopFor{value: fundAmount}(address(treasuryRebalancer), maxGas);

        // ── AirdropDistributor (VRF) ───────────────────────────────────────────
        // Pre-fund so prize payouts work: 3 winners × 0.01 ETH × 10 draws = 0.3 ETH
        AirdropDistributor airdropDistributor = new AirdropDistributor(
            3600,       // 1hr draw interval (testnet)
            3,          // 3 winners per draw
            0.01 ether  // 0.01 ETH prize per winner
        );
        (bool _ok4,) = address(airdropDistributor).call{value: 0.3 ether}("");
        require(_ok4, "AirdropDistributor fund failed");
        registrar.registerAutoLoopFor{value: fundAmount}(address(airdropDistributor), maxGas);

        // ── NFTReveal (VRF) ────────────────────────────────────────────────────
        uint256[] memory tiers = new uint256[](4);
        tiers[0] = 5000; tiers[1] = 3000; tiers[2] = 1500; tiers[3] = 500;
        string[] memory tierNames = new string[](4);
        tierNames[0] = "Common"; tierNames[1] = "Uncommon";
        tierNames[2] = "Rare";   tierNames[3] = "Legendary";

        NFTReveal nftReveal = new NFTReveal(
            100,                       // max supply
            0.001 ether,               // mint price
            block.timestamp + 1 hours, // reveal after 1hr (testnet — short window)
            tiers,
            tierNames
        );
        nftReveal.openMint();
        registrar.registerAutoLoopFor{value: fundAmount}(address(nftReveal), maxGas);

        // ── LotterySweepstakes (VRF) ───────────────────────────────────────────
        // Users fund by buying tickets; no pre-funding needed.
        LotterySweepstakes lotterySweepstakes = new LotterySweepstakes(
            0.001 ether,  // ticket price
            3600          // 1hr round interval (testnet)
        );
        registrar.registerAutoLoopFor{value: fundAmount}(address(lotterySweepstakes), maxGas);

        vm.stopBroadcast();

        // ── Console output ─────────────────────────────────────────────────────
        console.log("VaultDeadSwitch:         ", address(vaultDeadSwitch));
        console.log("YieldHarvester:          ", address(yieldHarvester));
        console.log("MockVault:               ", address(mockVault));
        console.log("AIAgentLoop:             ", address(aiAgentLoop));
        console.log("DAOExecutor:             ", address(daoExecutor));
        console.log("TreasuryRebalancer:      ", address(treasuryRebalancer));
        console.log("AirdropDistributor:      ", address(airdropDistributor));
        console.log("NFTReveal:               ", address(nftReveal));
        console.log("LotterySweepstakes:      ", address(lotterySweepstakes));
    }
}
