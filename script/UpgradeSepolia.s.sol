// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/AutoLoop.sol";
import "../src/AutoLoopRegistrar.sol";

/**
 * @title UpgradeSepolia
 * @notice Upgrades AutoLoop and AutoLoopRegistrar implementations on Sepolia.
 *         Reads ProxyAdmin addresses from the proxy's admin storage slot.
 *
 * Usage:
 *   source .env && forge script script/UpgradeSepolia.s.sol \
 *     --rpc-url $SEPOLIA_RPC_URL --broadcast
 */
contract UpgradeSepolia is Script {
    // Sepolia proxy addresses
    address constant AUTO_LOOP_PROXY = 0x311eB21A1f7C0f12Ea7995cd6c02855b1bDa2132;
    address constant REGISTRAR_PROXY = 0xDA2867844F77768451c2b5f208b4f78571fd82C1;

    // ProxyAdmin addresses (read from admin storage slot)
    address constant AUTO_LOOP_PROXY_ADMIN = 0x8133A04c3834165Dc1c7DFc07693A537Cb52E330;
    address constant REGISTRAR_PROXY_ADMIN = 0x1d2F2D0D8dd279ED3d1e2d8A9328Dd48Cc31110b;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Verify current state
        AutoLoop currentAutoLoop = AutoLoop(AUTO_LOOP_PROXY);
        console.log("Current AutoLoop version:", currentAutoLoop.version());
        console.log("Current baseFee:", currentAutoLoop.baseFee());

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementations
        AutoLoop newAutoLoopImpl = new AutoLoop();
        AutoLoopRegistrar newRegistrarImpl = new AutoLoopRegistrar();

        console.log("New AutoLoop impl:", address(newAutoLoopImpl));
        console.log("New Registrar impl:", address(newRegistrarImpl));

        // Upgrade AutoLoop proxy
        ProxyAdmin(AUTO_LOOP_PROXY_ADMIN).upgradeAndCall(
            ITransparentUpgradeableProxy(AUTO_LOOP_PROXY),
            address(newAutoLoopImpl),
            ""
        );

        // Upgrade Registrar proxy
        ProxyAdmin(REGISTRAR_PROXY_ADMIN).upgradeAndCall(
            ITransparentUpgradeableProxy(REGISTRAR_PROXY),
            address(newRegistrarImpl),
            ""
        );

        vm.stopBroadcast();

        // Verify upgrade preserved state
        AutoLoop upgraded = AutoLoop(AUTO_LOOP_PROXY);
        console.log("Post-upgrade version:", upgraded.version());
        console.log("Post-upgrade baseFee:", upgraded.baseFee());

        // Verify new function exists
        uint256 minBal = upgraded.minBalanceFor(address(0));
        console.log("minBalanceFor(0x0):", minBal);

        console.log("Upgrade complete!");
    }
}
