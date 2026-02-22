// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/AutoLoop.sol";
import "../src/AutoLoopRegistry.sol";
import "../src/AutoLoopRegistrar.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementations
        AutoLoop autoLoopImpl = new AutoLoop();
        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();

        // Deploy proxies
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            deployer,
            abi.encodeWithSignature("initialize(string)", "0.1.0")
        );

        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            deployer,
            abi.encodeWithSignature("initialize(address)", deployer)
        );

        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            deployer,
            abi.encodeWithSignature("initialize(address,address,address)", address(autoLoopProxy), address(registryProxy), deployer)
        );

        // Wire up registrar roles
        AutoLoop autoLoop = AutoLoop(address(autoLoopProxy));
        AutoLoopRegistry registry = AutoLoopRegistry(address(registryProxy));

        autoLoop.setRegistrar(address(registrarProxy));
        registry.setRegistrar(address(registrarProxy));

        vm.stopBroadcast();

        console.log("AutoLoop:", address(autoLoopProxy));
        console.log("AutoLoopRegistry:", address(registryProxy));
        console.log("AutoLoopRegistrar:", address(registrarProxy));
    }
}
