// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// GameLoopCompatible.sol imports the functions from both @chainlink/contracts/src/v0.8/AutomationBase.sol
// and GameLoopCompatibleInterface.sol
import "../GameLoopCompatible.sol";
import "../GameLoopRegistrar.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract NumberGoUp is GameLoopCompatibleInterface, AccessControl {
    uint256 public number;
    uint256 public interval;
    uint256 public lastTimeStamp;

    constructor(uint256 updateInterval) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        interval = updateInterval;
        lastTimeStamp = block.timestamp;
        number = 0;
    }

    function registerGameLoop(address registrarAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Register game loop
        bool success = GameLoopRegistrar(registrarAddress).registerGameLoop();
        if (!success) {
            revert("unable to register game loop");
        }
    }

    function unregisterGameLoop(address registrarAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Unegister game loop
        GameLoopRegistrar(registrarAddress).unregisterGameLoop();
    }

    // Required functions from GameLoopCompatibleInterface.sol
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady)
    {
        loopIsReady = (block.timestamp - lastTimeStamp) > interval;
    }

    function progressLoop() public override {
        // Re-check logic from shouldProgressLoop()
        if ((block.timestamp - lastTimeStamp) > interval) {
            updateGame();
        }
    }

    function updateGame() internal {
        // this is what gets called on each game loop cycle
        lastTimeStamp = block.timestamp;
        ++number;
    }
}
