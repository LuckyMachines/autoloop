// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// AutoLoopCompatible.sol imports the functions from both @chainlink/contracts/src/v0.8/AutomationBase.sol
// and AutoLoopCompatibleInterface.sol
import "../AutoLoopCompatible.sol";
import "../AutoLoopRegistrar.sol";

contract NumberGoUp is AutoLoopCompatible {
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

    function registerAutoLoop(address registrarAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Register auto loop
        bool success = AutoLoopRegistrar(registrarAddress).registerAutoLoop();
        if (!success) {
            revert("unable to register auto loop");
        }
    }

    function unregisterAutoLoop(address registrarAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Unegister auto loop
        AutoLoopRegistrar(registrarAddress).unregisterAutoLoop();
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
        lastTimeStamp = block.timestamp;
        ++number;
        ++_loopID;
    }
}
