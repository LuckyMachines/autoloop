// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "./AutoLoopVRFCompatible.sol";

/**
 * @title AutoLoopHybridVRFCompatible
 * @notice Abstract base for AutoLoop contracts that selectively use VRF randomness.
 * @dev Extends AutoLoopVRFCompatible. The contract decides per-tick whether it needs
 *      VRF randomness via `_needsVRF(loopID)`. The worker reads the flag from
 *      `shouldProgressLoop()` and only generates a VRF proof when requested.
 *
 *      This dramatically reduces gas costs for contracts that only need occasional
 *      randomness (e.g., every 10th tick for a random event).
 *
 *      progressWithData encoding from shouldProgressLoop():
 *        abi.encode(bool needsVRF, uint256 loopID, bytes gameData)
 *
 *      When needsVRF=true, the worker wraps in a VRF envelope before calling progressLoop().
 *      When needsVRF=false, the worker sends the data as-is.
 *
 *      Contract devs override:
 *        - _shouldProgress() — timing/readiness logic
 *        - _needsVRF(loopID) — when to request VRF (e.g., loopID % 10 == 0)
 *        - _onTick(gameData) — standard tick logic
 *        - _onVRFTick(randomness, gameData) — VRF tick logic
 */
abstract contract AutoLoopHybridVRFCompatible is AutoLoopVRFCompatible {
    /// @notice ERC165 interface ID for hybrid VRF contracts
    bytes4 public constant HYBRID_VRF_INTERFACE_ID =
        bytes4(keccak256("AutoLoopHybridVRFCompatible"));

    /// @notice Emitted on a standard (non-VRF) tick
    event StandardTick(uint256 indexed loopID, uint256 timestamp);

    /// @notice Emitted on a VRF tick with randomness
    event HybridVRFTick(uint256 indexed loopID, bytes32 randomness, uint256 timestamp);

    /**
     * @notice Determine if the contract needs VRF randomness for this tick.
     * @dev Override with custom logic, e.g. `return loopID % 10 == 0;`
     * @param loopID The current loop iteration number.
     * @return True if this tick should include a VRF proof.
     */
    function _needsVRF(uint256 loopID) internal view virtual returns (bool);

    /**
     * @notice Check if the loop should progress and return game-specific data.
     * @dev Override with timing logic (e.g., interval checks).
     * @return ready True if the loop is ready to progress.
     * @return gameData Arbitrary bytes to pass through to _onTick/_onVRFTick.
     */
    function _shouldProgress()
        internal
        view
        virtual
        returns (bool ready, bytes memory gameData);

    /**
     * @notice Called on standard ticks (no VRF randomness).
     * @param gameData The game-specific data from _shouldProgress().
     */
    function _onTick(bytes memory gameData) internal virtual;

    /**
     * @notice Called on VRF ticks with verified randomness.
     * @param randomness The verified VRF random value.
     * @param gameData The game-specific data from _shouldProgress().
     */
    function _onVRFTick(bytes32 randomness, bytes memory gameData) internal virtual;

    /**
     * @notice AutoLoop interface — checks readiness and encodes the hybrid flag.
     * @dev Encodes (needsVRF, loopID, gameData) so the worker knows whether
     *      to generate a VRF proof for this tick.
     */
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        (bool ready, bytes memory gameData) = _shouldProgress();
        loopIsReady = ready;
        bool needsVRF = _needsVRF(_loopID);
        progressWithData = abi.encode(needsVRF, _loopID, gameData);
    }

    /**
     * @notice AutoLoop interface — routes to _onTick or _onVRFTick based on VRF flag.
     * @dev The worker sends either raw hybrid data (non-VRF tick) or a VRF envelope
     *      (VRF tick). This function detects which format was sent and routes accordingly.
     *
     *      For VRF ticks: the worker wraps in VRF envelope, so we unwrap the envelope
     *      first to get the inner hybrid data, then decode the flag and call _onVRFTick.
     *
     *      For standard ticks: the worker sends the raw encoded (needsVRF, loopID, gameData),
     *      so we decode directly and call _onTick.
     */
    function progressLoop(bytes calldata progressWithData) external override {
        // Decode the first bool to determine tick type.
        // For standard ticks, progressWithData = abi.encode(false, loopID, gameData)
        // For VRF ticks, the worker wraps in VRF envelope, so we need to unwrap first.
        //
        // Detection strategy: try to decode as VRF envelope. If the first byte (vrfVersion)
        // is 1 and it's a VRF tick, we unwrap. Otherwise treat as standard.
        //
        // Since VRF envelope starts with uint8(1) and standard starts with bool(false/true)
        // which is uint8(0/1), we use the hybrid flag inside the inner data to route.

        // Try VRF envelope first — the worker only wraps when needsVRF was true
        // VRF envelope: abi.encode(uint8 vrfVersion, uint256[4] proof, uint256[2] uPoint, uint256[4] vComponents, bytes innerData)
        // Standard: abi.encode(bool needsVRF, uint256 loopID, bytes gameData)
        //
        // We can distinguish them by size: VRF envelope is much larger (>= 640 bytes for the proof alone)
        // Standard encoding is much smaller.

        if (progressWithData.length >= 640) {
            // VRF tick — unwrap envelope and verify proof
            (bytes32 randomness, bytes memory innerData) = _verifyAndExtractRandomness(
                progressWithData,
                tx.origin
            );

            // innerData is the original abi.encode(needsVRF, loopID, gameData)
            (bool needsVRF, uint256 loopID, bytes memory gameData) = abi.decode(
                innerData,
                (bool, uint256, bytes)
            );

            require(needsVRF, "VRF envelope sent for non-VRF tick");
            require(loopID == _loopID, "Stale loop ID");

            _onVRFTick(randomness, gameData);

            emit HybridVRFTick(_loopID, randomness, block.timestamp);
            ++_loopID;
        } else {
            // Standard tick — decode directly
            (bool needsVRF, uint256 loopID, bytes memory gameData) = abi.decode(
                progressWithData,
                (bool, uint256, bytes)
            );

            require(!needsVRF, "VRF required but no proof provided");
            require(loopID == _loopID, "Stale loop ID");

            _onTick(gameData);

            emit StandardTick(_loopID, block.timestamp);
            ++_loopID;
        }
    }

    /**
     * @notice ERC165 support — advertises hybrid VRF compatibility.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == HYBRID_VRF_INTERFACE_ID ||
            super.supportsInterface(interfaceId);
    }
}
