// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/AutoLoop.sol";
import "../src/AutoLoopRegistry.sol";
import "../src/AutoLoopRegistrar.sol";

/**
 * @title Deploy
 * @notice Deployment script with security improvements:
 *         - C1: Accepts PROXY_ADMIN env var (multisig) instead of using deployer EOA
 *         - M7: Uses abi.encodeCall() instead of fragile encodeWithSignature
 *         - Post-deployment verification assertions
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // C1: Use a dedicated proxy admin address (should be a multisig / timelock).
        // Falls back to deployer if PROXY_ADMIN is not set (for local dev only).
        address proxyAdminAddress = vm.envOr("PROXY_ADMIN", deployer);

        // Warn if proxy admin is the deployer EOA (acceptable for testnet, not mainnet)
        if (proxyAdminAddress == deployer) {
            console.log("WARNING: Proxy admin is deployer EOA. Use a multisig for mainnet!");
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementations
        AutoLoop autoLoopImpl = new AutoLoop();
        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();

        // Deploy proxies (M7: use abi.encodeCall for type safety)
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            proxyAdminAddress,
            abi.encodeCall(AutoLoop.initialize, ("0.1.0"))
        );

        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            proxyAdminAddress,
            abi.encodeCall(AutoLoopRegistry.initialize, (deployer))
        );

        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            proxyAdminAddress,
            abi.encodeCall(
                AutoLoopRegistrar.initialize,
                (address(autoLoopProxy), address(registryProxy), deployer)
            )
        );

        // Wire up registrar roles
        AutoLoop autoLoop = AutoLoop(address(autoLoopProxy));
        AutoLoopRegistry registry = AutoLoopRegistry(address(registryProxy));

        autoLoop.setRegistrar(address(registrarProxy));
        registry.setRegistrar(address(registrarProxy));

        vm.stopBroadcast();

        // Post-deployment verification assertions
        require(
            autoLoop.hasRole(autoLoop.DEFAULT_ADMIN_ROLE(), deployer),
            "Deploy: AutoLoop admin role not set"
        );
        require(
            registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), deployer),
            "Deploy: Registry admin role not set"
        );
        require(
            autoLoop.hasRole(autoLoop.REGISTRAR_ROLE(), address(registrarProxy)),
            "Deploy: Registrar role not granted on AutoLoop"
        );
        require(
            registry.hasRole(registry.REGISTRAR_ROLE(), address(registrarProxy)),
            "Deploy: Registrar role not granted on Registry"
        );

        console.log("AutoLoop:", address(autoLoopProxy));
        console.log("AutoLoopRegistry:", address(registryProxy));
        console.log("AutoLoopRegistrar:", address(registrarProxy));
        console.log("Proxy Admin:", proxyAdminAddress);
    }
}
