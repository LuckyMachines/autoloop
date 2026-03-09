// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../src/AutoLoopCompatible.sol";
import "../src/AutoLoopRegistrar.sol";

/// @title AutoCounter
/// @notice The simplest AutoLoop example: increments a counter at a fixed interval.
/// @dev Deploy, register with AutoLoop, fund, and watch the counter go up.
contract AutoCounter is AutoLoopCompatible {
    event CounterIncremented(uint256 indexed count, uint256 timestamp);

    uint256 public count;
    uint256 public interval;
    uint256 public lastTimestamp;

    constructor(uint256 _interval) {
        require(_interval > 0, "Interval must be > 0");
        interval = _interval;
        lastTimestamp = block.timestamp;
    }

    /// @notice Register this contract with AutoLoop
    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = block.timestamp >= lastTimestamp + interval;
        progressWithData = abi.encode(_loopID);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        uint256 loopID = abi.decode(progressWithData, (uint256));
        require(block.timestamp >= lastTimestamp + interval, "Too soon");
        require(loopID == _loopID, "Stale loop ID");

        count++;
        lastTimestamp = block.timestamp;
        ++_loopID;

        emit CounterIncremented(count, block.timestamp);
    }
}
