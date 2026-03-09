// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../src/AutoLoopHybridVRFCompatible.sol";
import "../src/AutoLoopRegistrar.sol";

/// @title HybridGame
/// @notice Demo contract showing hybrid VRF: cheap standard ticks with occasional VRF randomness.
/// @dev Ticks every `interval` seconds. Every 10th tick requests VRF to spawn a random event.
///      Standard ticks (~90k gas) increment the score. VRF ticks (~240k gas) trigger a special event.
contract HybridGame is AutoLoopHybridVRFCompatible {
    event ScoreUpdated(uint256 indexed loopID, uint256 newScore, uint256 timestamp);
    event RandomEvent(uint256 indexed loopID, uint256 eventType, uint256 magnitude, bytes32 randomness, uint256 timestamp);

    uint256 public score;
    uint256 public totalTicks;
    uint256 public totalVRFTicks;
    uint256 public interval;
    uint256 public lastTimestamp;
    uint256 public vrfFrequency;

    // Last random event details
    uint256 public lastEventType;
    uint256 public lastEventMagnitude;
    bytes32 public lastRandomness;

    // Event types
    uint256 public constant EVENT_BONUS = 0;
    uint256 public constant EVENT_MULTIPLIER = 1;
    uint256 public constant EVENT_JACKPOT = 2;
    uint256 public constant EVENT_TYPES = 3;

    constructor(uint256 _interval, uint256 _vrfFrequency) {
        require(_interval > 0, "Interval must be > 0");
        require(_vrfFrequency > 0, "VRF frequency must be > 0");
        interval = _interval;
        vrfFrequency = _vrfFrequency;
        lastTimestamp = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    /// @notice VRF is needed every `vrfFrequency` ticks (e.g., every 10th tick).
    function _needsVRF(uint256 loopID) internal view override returns (bool) {
        return loopID % vrfFrequency == 0;
    }

    /// @notice Check if enough time has passed since the last tick.
    function _shouldProgress()
        internal
        view
        override
        returns (bool ready, bytes memory gameData)
    {
        ready = block.timestamp >= lastTimestamp + interval;
        gameData = ""; // no extra game data needed
    }

    /// @notice Standard tick — increment score by 1.
    function _onTick(bytes memory) internal override {
        score += 1;
        totalTicks++;
        lastTimestamp = block.timestamp;

        emit ScoreUpdated(_loopID, score, block.timestamp);
    }

    /// @notice VRF tick — use randomness to spawn a special event.
    function _onVRFTick(bytes32 randomness, bytes memory) internal override {
        uint256 rand = uint256(randomness);

        // Determine event type (0-2)
        uint256 eventType = rand % EVENT_TYPES;

        // Determine magnitude (1-100)
        uint256 magnitude = (rand / EVENT_TYPES) % 100 + 1;

        // Apply event
        if (eventType == EVENT_BONUS) {
            score += magnitude;
        } else if (eventType == EVENT_MULTIPLIER) {
            // 2x-4x multiplier on a small bonus
            uint256 multiplier = (magnitude % 3) + 2;
            score += 10 * multiplier;
        } else if (eventType == EVENT_JACKPOT) {
            score += magnitude * 10;
        }

        lastEventType = eventType;
        lastEventMagnitude = magnitude;
        lastRandomness = randomness;
        totalTicks++;
        totalVRFTicks++;
        lastTimestamp = block.timestamp;

        emit RandomEvent(_loopID, eventType, magnitude, randomness, block.timestamp);
    }
}
