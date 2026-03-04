// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/AutoLoopCompatible.sol";

/**
 * @title TimeBasedTrigger
 * @notice Generic interval-based trigger that fires every N seconds.
 * @dev Extend this contract and override _onLoop() to add custom logic.
 *
 * Example usage:
 *   contract MyTask is TimeBasedTrigger {
 *       constructor() TimeBasedTrigger(3600) {} // every hour
 *       function _onLoop() internal override { /* your logic */ }
 *   }
 */
abstract contract TimeBasedTrigger is AutoLoopCompatible {
    uint256 public immutable interval;
    uint256 public lastExecuted;

    constructor(uint256 _interval) {
        require(_interval > 0, "Interval must be > 0");
        interval = _interval;
        lastExecuted = block.timestamp;
    }

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = block.timestamp >= lastExecuted + interval;
        progressWithData = "";
    }

    function progressLoop(bytes calldata) external override {
        require(block.timestamp >= lastExecuted + interval, "Too soon");
        lastExecuted = block.timestamp;
        _onLoop();
    }

    /**
     * @dev Override this function with your custom logic.
     */
    function _onLoop() internal virtual;
}
