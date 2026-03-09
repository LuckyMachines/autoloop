// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../src/AutoLoopVRFCompatible.sol";
import "../src/AutoLoopRegistrar.sol";

/// @title CoinFlipper
/// @notice VRF-powered coin flip with provably fair randomness.
/// @dev Each tick flips a coin using ECVRF. Tracks heads/tails history.
contract CoinFlipper is AutoLoopVRFCompatible {
    event CoinFlipped(uint256 indexed flipNumber, bool isHeads, bytes32 randomness, uint256 timestamp);

    uint256 public totalFlips;
    uint256 public headsCount;
    uint256 public tailsCount;
    uint256 public interval;
    uint256 public lastTimestamp;
    bool public lastResult; // true = heads

    // Last 20 results
    bool[20] public history;
    uint256 public historyIndex;

    constructor(uint256 _interval) {
        require(_interval > 0, "Interval must be > 0");
        interval = _interval;
        lastTimestamp = block.timestamp;
    }

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
        (bytes32 randomness, bytes memory gameData) = _verifyAndExtractRandomness(
            progressWithData,
            tx.origin
        );

        uint256 loopID = abi.decode(gameData, (uint256));
        require(block.timestamp >= lastTimestamp + interval, "Too soon");
        require(loopID == _loopID, "Stale loop ID");

        bool isHeads = uint256(randomness) % 2 == 0;

        totalFlips++;
        lastResult = isHeads;
        lastTimestamp = block.timestamp;

        if (isHeads) {
            headsCount++;
        } else {
            tailsCount++;
        }

        history[historyIndex] = isHeads;
        historyIndex = (historyIndex + 1) % 20;

        emit CoinFlipped(_loopID, isHeads, randomness, block.timestamp);
        ++_loopID;
    }

    function getHistory() external view returns (bool[20] memory) {
        return history;
    }

    function headsPercentage() external view returns (uint256) {
        if (totalFlips == 0) return 50;
        return (headsCount * 100) / totalFlips;
    }
}
