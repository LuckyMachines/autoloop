// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopCompatible.sol";
import "../AutoLoopRegistrar.sol";

contract NumberGoUp is AutoLoopCompatible {
    event GameUpdated(uint256 indexed timeStamp);

    uint256 public number;
    uint256 public interval;
    uint256 public lastTimeStamp;

    constructor(uint256 updateInterval) {
        interval = updateInterval;
        lastTimeStamp = block.timestamp;
        number = 0;
    }

    function registerAutoLoop(
        address registrarAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        // Register auto loop
        bool success = AutoLoopRegistrar(registrarAddress).registerAutoLoop();
        if (!success) {
            revert("unable to register auto loop");
        }
    }

    function deregisterAutoLoop(
        address registrarAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrarAddress).deregisterAutoLoop();
    }

    // Required functions from AutoLoopCompatibleInterface.sol
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
        // this is what gets called on each auto loop cycle
        emit GameUpdated(block.timestamp);
        lastTimeStamp = block.timestamp;
        ++number;
        ++_loopID;
    }
}
