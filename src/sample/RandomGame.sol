// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title RandomGame
 * @notice Sample dice-roll game demonstrating AutoLoop VRF integration.
 * @dev On each tick, the controller provides an ECVRF proof. The contract verifies it
 *      and uses the VRF output to produce a fair 1-6 dice roll. Serves as the reference
 *      implementation for AutoLoopVRFCompatible contracts.
 */
contract RandomGame is AutoLoopVRFCompatible {
    event DiceRolled(
        uint256 indexed loopID,
        uint256 roll,
        bytes32 randomness,
        uint256 timestamp
    );

    /// @notice The last dice roll result (1-6)
    uint256 public lastRoll;

    /// @notice Total number of rolls performed
    uint256 public totalRolls;

    /// @notice Minimum time between rolls (seconds)
    uint256 public interval;

    /// @notice Timestamp of last roll
    uint256 public lastTimeStamp;

    /// @notice History of recent rolls (last 10)
    uint256[10] public rollHistory;
    uint256 public historyIndex;

    constructor(uint256 updateInterval) {
        interval = updateInterval;
        lastTimeStamp = block.timestamp;
    }

    // ---------------------------------------------------------------
    //  AutoLoop registration helpers
    // ---------------------------------------------------------------

    function registerAutoLoop(
        address registrarAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
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

    // ---------------------------------------------------------------
    //  AutoLoopCompatibleInterface implementation
    // ---------------------------------------------------------------

    /**
     * @notice Check if a new roll is ready. Returns the loop ID as game data.
     */
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = (block.timestamp - lastTimeStamp) > interval;
        // Pass the current loopID so the worker can compute the correct seed
        progressWithData = abi.encode(_loopID);
    }

    /**
     * @notice Execute a dice roll with VRF-verified randomness.
     * @dev The progressWithData is a VRF envelope wrapping the game data.
     *      The controller address is tx.origin (the worker wallet).
     */
    function progressLoop(bytes calldata progressWithData) external override {
        // Verify VRF proof and extract randomness + game data
        (bytes32 randomness, bytes memory gameData) = _verifyAndExtractRandomness(
            progressWithData,
            tx.origin
        );

        // Decode game data (the loop ID from shouldProgressLoop)
        uint256 loopID = abi.decode(gameData, (uint256));

        // Re-check timing and loop ID
        if ((block.timestamp - lastTimeStamp) > interval && loopID == _loopID) {
            _rollDice(randomness);
        }
    }

    // ---------------------------------------------------------------
    //  Internal game logic
    // ---------------------------------------------------------------

    function _rollDice(bytes32 randomness) internal {
        // Compute dice roll: 1-6 from VRF output
        uint256 roll = (uint256(randomness) % 6) + 1;

        lastRoll = roll;
        lastTimeStamp = block.timestamp;
        totalRolls++;

        // Store in history ring buffer
        rollHistory[historyIndex] = roll;
        historyIndex = (historyIndex + 1) % 10;

        emit DiceRolled(_loopID, roll, randomness, block.timestamp);

        ++_loopID;
    }

    // ---------------------------------------------------------------
    //  View helpers
    // ---------------------------------------------------------------

    /**
     * @notice Get all 10 recent rolls.
     */
    function getRecentRolls() external view returns (uint256[10] memory) {
        return rollHistory;
    }
}
