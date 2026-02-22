// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Script.sol";
import "../src/sample/NumberGoUp.sol";

contract DeploySample is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        NumberGoUp game = new NumberGoUp(30); // 30 second interval

        vm.stopBroadcast();

        console.log("NumberGoUp:", address(game));
    }
}
