// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title AIAgentLoop
/// @notice Fires a neutral on-chain AgentTick on a fixed schedule. Off-chain AI workers
///         listen for the event, run inference, and submit signed actions. The scheduling
///         itself belongs to no participant — operators, users, and competitors all have
///         conflicting interests in when the agent fires.
/// @dev Demonstrates: neutral scheduling for AI agent execution loops.
///      The agent intelligence lives off-chain. AutoLoop provides the clock nobody owns.
contract AIAgentLoop is AutoLoopCompatible {
    // ── State ──────────────────────────────────────────────────────────────────

    uint256 public tickInterval;
    uint256 public lastTick;
    uint256 public totalTicks;

    /// @notice IPFS CID or content hash of the current agent instructions / system prompt.
    bytes32 public instructionHash;

    /// @notice Optional: maximum number of ticks before the agent loop stops (0 = unlimited).
    uint256 public maxTicks;

    uint256 public protocolFeeBalance;

    // ── Events ─────────────────────────────────────────────────────────────────

    /// @notice Off-chain workers listen for this event to know when to run inference.
    event AgentTick(
        uint256 indexed loopID,
        uint256 indexed tickNumber,
        bytes32 instructionHash,
        uint256 timestamp
    );

    event InstructionsUpdated(bytes32 indexed oldHash, bytes32 indexed newHash);
    event MaxTicksUpdated(uint256 oldMax, uint256 newMax);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _tickInterval     Seconds between ticks
    /// @param _instructionHash  IPFS CID (as bytes32) of initial agent instructions
    /// @param _maxTicks         Maximum ticks (0 = unlimited)
    constructor(uint256 _tickInterval, bytes32 _instructionHash, uint256 _maxTicks) {
        require(_tickInterval > 0, "AIAgentLoop: interval=0");
        tickInterval = _tickInterval;
        instructionHash = _instructionHash;
        maxTicks = _maxTicks;
        lastTick = block.timestamp;
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool withinMaxTicks = maxTicks == 0 || totalTicks < maxTicks;
        loopIsReady = withinMaxTicks && (block.timestamp - lastTick) >= tickInterval;
        progressWithData = abi.encode(_loopID, instructionHash);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID, bytes32 instrHash) = abi.decode(progressWithData, (uint256, bytes32));
        require((block.timestamp - lastTick) >= tickInterval, "AIAgentLoop: too soon");
        require(loopID == _loopID, "AIAgentLoop: stale loop id");
        require(maxTicks == 0 || totalTicks < maxTicks, "AIAgentLoop: max ticks reached");

        lastTick = block.timestamp;
        ++_loopID;
        ++totalTicks;

        emit AgentTick(loopID, totalTicks, instrHash, block.timestamp);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    /// @notice Update agent instructions (e.g. new system prompt uploaded to IPFS).
    function setInstructionHash(bytes32 _hash) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit InstructionsUpdated(instructionHash, _hash);
        instructionHash = _hash;
    }

    function setTickInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "AIAgentLoop: interval=0");
        tickInterval = _interval;
    }

    function setMaxTicks(uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MaxTicksUpdated(maxTicks, _max);
        maxTicks = _max;
    }

    receive() external payable {}
}
