// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/AutoLoop.sol";

/**
 * @title ConfigureSepolia
 * @notice Post-deploy configuration for Sepolia testnet:
 *         - Sets BASE_FEE to 2% (vs 70% mainnet) to stretch testnet ETH
 *         - Keeps 50/50 protocol/controller split to demo the fee mechanic
 *
 * Usage:
 *   PRIVATE_KEY=0x... AUTO_LOOP=0x... forge script script/ConfigureSepolia.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL --broadcast
 */
contract ConfigureSepolia is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address autoLoopProxy = vm.envAddress("AUTO_LOOP");

        AutoLoop autoLoop = AutoLoop(autoLoopProxy);

        console.log("Current BASE_FEE:", autoLoop.baseFee());
        console.log("Setting BASE_FEE to 2%...");

        vm.startBroadcast(deployerPrivateKey);

        autoLoop.setBaseFee(2);

        vm.stopBroadcast();

        console.log("New BASE_FEE:", autoLoop.baseFee());
        console.log("Controller fee portion:", autoLoop.controllerFeePortion());
        console.log("Protocol fee portion:", autoLoop.protocolFeePortion());
    }
}
