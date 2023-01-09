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

    uint256 _loopID;

    constructor(uint256 updateInterval) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        interval = updateInterval;
        lastTimeStamp = block.timestamp;
        number = 0;
        _loopID = 1;
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
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = (block.timestamp - lastTimeStamp) > interval;
        // we pass a loop ID to avoid running the same update twice
        progressWithData = bytes(abi.encode(_loopID));
    }

    function progressLoop(bytes calldata progressWithData) external override {
        // Decode data sent from shouldProgressLoop()
        uint256 loopID = abi.decode(progressWithData, (uint256));
        // Re-check logic from shouldProgressLoop()
        if ((block.timestamp - lastTimeStamp) > interval && loopID == _loopID) {
            updateGame();
        }
    }

    function updateGame() internal {
        // this is what gets called on each game loop cycle
        lastTimeStamp = block.timestamp;
        ++number;
        ++_loopID;
    }
}
