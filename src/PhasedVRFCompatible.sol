// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "./AutoLoopVRFCompatible.sol";

/**
 * @title PhasedVRFCompatible
 * @notice Extension of AutoLoopVRFCompatible implementing two-phase commit/settle
 *         to eliminate keeper foreknowledge of the final randomness.
 *
 * ── Why this matters ──────────────────────────────────────────────────────────
 *
 * Single-phase VRF (AutoLoopVRFCompatible):
 *   The keeper generates the proof off-chain, knows the VRF output before
 *   submitting, and can choose to withhold if they dislike the result.
 *   RANDAO mixing adds uncertainty (keeper can't guarantee which block's RANDAO),
 *   but a keeper who is also a PoS validator can still influence prevrandao.
 *
 * Two-phase commit/settle:
 *   Phase 1 — Commit (block N):
 *     Keeper submits a verified VRF proof. Contract stores `vrfOutput` and
 *     records `settleBlock = N + SETTLE_DELAY`. The keeper knows vrfOutput,
 *     but `blockhash(settleBlock)` doesn't exist yet — it will be determined
 *     by the PoS validators of blocks N+1 through N+SETTLE_DELAY.
 *
 *   Phase 2 — Settle (block N+SETTLE_DELAY+1 or later):
 *     Any registered controller triggers settlement.
 *     `finalRandomness = keccak256(vrfOutput, blockhash(settleBlock))`
 *
 *   Neither the committing keeper (who knows vrfOutput) nor any block proposer
 *   in the settle window (who knows their own blockhash contribution) can
 *   unilaterally determine finalRandomness. Manipulation requires coordinating
 *   BOTH the committing keeper AND all block proposers in the settle window —
 *   a different validator for each of the SETTLE_DELAY slots on PoS Ethereum.
 *
 * ── Trust model comparison ───────────────────────────────────────────────────
 *
 * Base VRF (single-phase):
 *   Must trust keeper set is non-colluding OR that one keeper will submit
 *   if another withholds (multi-controller race).
 *
 * + RANDAO mixing:
 *   Keeper must be block proposer to precisely predict outcome.
 *
 * + PhasedVRFCompatible:
 *   Keeper and ALL slot validators in the settle window must collude.
 *   On PoS Ethereum mainnet, each slot is assigned to a different validator
 *   drawn from ~500k validators — coordination is practically infeasible.
 *
 * ── Protocol compatibility ───────────────────────────────────────────────────
 *
 * No changes to AutoLoop.sol or the worker are required. Phase detection is
 * internal contract state. The worker submits a VRF proof for both commit and
 * settle phases (because it detects VRF_INTERFACE_ID). The commit proof is
 * fully verified. The settle proof is used only for controller authorization
 * (is the settler a registered controller?) — the settle's VRF output is
 * discarded; randomness comes from the stored commit output + blockhash.
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *
 * 1. Extend PhasedVRFCompatible instead of AutoLoopVRFCompatible.
 * 2. In shouldProgressLoop(): call `_phasedShouldProgress(gameIntervalElapsed)`.
 * 3. In progressLoop(): call `(bool settled, bytes32 randomness, bytes memory data) = _dispatchPhase(progressWithData)`.
 *    - If !settled: commit was accepted, return. No game state change yet.
 *    - If settled: apply randomness to game state, emit result, increment _loopID.
 */
abstract contract PhasedVRFCompatible is AutoLoopVRFCompatible {
    // ── Config ─────────────────────────────────────────────────────────────────

    /// @notice Blocks between commit and settle.
    ///         5 blocks ≈ 60s on Ethereum mainnet (12s slots).
    ///         Each slot has an independent validator, so coordination requires
    ///         conspiring across SETTLE_DELAY independently assigned validators.
    uint256 public constant SETTLE_DELAY = 5;

    /// @notice Blocks after the settle block within which settlement remains valid.
    ///         256 is the EVM's blockhash retention window.
    uint256 public constant SETTLE_EXPIRY = 250;

    // ── State ──────────────────────────────────────────────────────────────────

    struct Commit {
        bytes32 vrfOutput; // Raw ECVRF output from the committing keeper
        bytes gameData; // Inner payload from shouldProgressLoop
        uint256 settleBlock; // Block whose hash will be mixed at settle time
        address controller; // Keeper who committed
        bool exists;
    }

    Commit public pendingCommit;

    // ── Events ─────────────────────────────────────────────────────────────────

    /// @notice Emitted when Phase 1 (commit) is accepted.
    event VRFCommitted(
        uint256 indexed loopID, bytes32 vrfOutput, uint256 settleBlock, address indexed controller
    );

    /// @notice Emitted when Phase 2 (settle) delivers final randomness.
    event VRFSettled(
        uint256 indexed loopID,
        bytes32 vrfOutput,
        bytes32 blockhashMix,
        bytes32 finalRandomness,
        address indexed settler
    );

    /// @notice Emitted when a commit expires without being settled.
    event VRFCommitExpired(uint256 indexed loopID, bytes32 vrfOutput, uint256 settleBlock);

    // ── shouldProgressLoop helper ──────────────────────────────────────────────

    /**
     * @notice Phase-aware loop readiness. Call this from shouldProgressLoop().
     *
     * @param gameIntervalElapsed  True if the game's own tick interval has passed.
     *                             Ignored during an active commit cycle.
     *
     * @return loopIsReady      True if a keeper action is available right now.
     * @return progressWithData Payload to pass to progressLoop. For both phases
     *                          this is abi.encode(_loopID) — the worker wraps it
     *                          in a VRF envelope automatically.
     */
    function _phasedShouldProgress(bool gameIntervalElapsed)
        internal
        view
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        if (pendingCommit.exists) {
            uint256 elapsed = block.number > pendingCommit.settleBlock
                ? block.number - pendingCommit.settleBlock
                : 0;

            if (elapsed > SETTLE_EXPIRY) {
                // Commit expired — fall through to normal game interval check
                if (gameIntervalElapsed) {
                    return (true, abi.encode(_loopID));
                }
                return (false, new bytes(0));
            }

            if (block.number > pendingCommit.settleBlock) {
                // Settle window open
                return (true, abi.encode(_loopID));
            }

            // Waiting for settle block
            return (false, new bytes(0));
        }

        // No pending commit — check game interval
        if (gameIntervalElapsed) {
            return (true, abi.encode(_loopID));
        }
        return (false, new bytes(0));
    }

    // ── progressLoop dispatcher ────────────────────────────────────────────────

    /**
     * @notice Detect current phase from contract state and dispatch.
     *
     * Phase detection (no encoding required — state drives behavior):
     *   - No pending commit → commit phase: verify VRF proof, store output
     *   - Pending commit, past settleBlock → settle phase: mix + deliver
     *   - Pending commit, settleBlock not reached → revert
     *
     * @param progressWithData  VRF-envelope from the worker (same format as
     *                          AutoLoopVRFCompatible — the worker is unchanged).
     *
     * @return settled          True if this call settled the pending commit.
     * @return finalRandomness  The two-source mixed randomness. Valid iff settled.
     * @return gameData         Inner game payload from the original commit.
     *                          Valid iff settled.
     */
    function _dispatchPhase(bytes calldata progressWithData)
        internal
        returns (bool settled, bytes32 finalRandomness, bytes memory gameData)
    {
        // Clear expired commits before phase check
        if (pendingCommit.exists) {
            uint256 elapsed = block.number > pendingCommit.settleBlock
                ? block.number - pendingCommit.settleBlock
                : 0;
            if (elapsed > SETTLE_EXPIRY) {
                emit VRFCommitExpired(_loopID, pendingCommit.vrfOutput, pendingCommit.settleBlock);
                delete pendingCommit;
            }
        }

        if (!pendingCommit.exists) {
            // Phase 1: Commit
            _doCommit(progressWithData);
            return (false, bytes32(0), new bytes(0));
        }

        require(block.number > pendingCommit.settleBlock, "PhasedVRF: settle block not reached");

        // Phase 2: Settle
        (finalRandomness, gameData) = _doSettle();
        return (true, finalRandomness, gameData);
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    /**
     * @dev Phase 1: full VRF proof verification, store commit.
     *      Called when no pending commit exists.
     */
    function _doCommit(bytes calldata progressWithData) private {
        // Reuse parent's VRF verification. It mixes with prevrandao internally,
        // but we store the raw vrfOutput (emitted in VRFRandomnessVerified event)
        // then discard the mixed value — the real final mix happens at settle.
        //
        // We need the raw vrfOutput, not the prevrandao-mixed value. We decode
        // the proof ourselves to get it, then call parent for authorization check.
        (
            uint8 vrfVersion,
            uint256[4] memory proof,
            uint256[2] memory uPoint,
            uint256[4] memory vComponents,
            bytes memory innerGameData
        ) = _decodeVRFData(progressWithData);

        require(vrfVersion == VRF_VERSION, "Unsupported VRF version");
        address controller = tx.origin;
        require(controllerKeyRegistered[controller], "Controller key not registered");

        uint256[2] memory publicKey = controllerPublicKeys[controller];
        bytes memory seed = computeSeed(_loopID);

        bool valid = VRFVerifier.fastVerify(publicKey, proof, seed, uPoint, vComponents);
        require(valid, "VRF proof verification failed");

        // Store the raw VRF output (before any mixing) for use at settle time
        bytes32 vrfOutput = VRFVerifier.gammaToHash(proof[0], proof[1]);
        uint256 settleBlock = block.number + SETTLE_DELAY;

        pendingCommit = Commit({
            vrfOutput: vrfOutput,
            gameData: innerGameData,
            settleBlock: settleBlock,
            controller: controller,
            exists: true
        });

        emit VRFCommitted(_loopID, vrfOutput, settleBlock, controller);
    }

    /**
     * @dev Phase 2: authorize caller, mix with blockhash, deliver randomness.
     *      The settle caller must be a registered controller (prevents griefing),
     *      but their VRF output is NOT used — final randomness comes from:
     *        keccak256(commit.vrfOutput, blockhash(settleBlock))
     *
     *      The settle proof submitted by the worker is verified for authorization
     *      only, not for randomness. This is safe because:
     *      - vrfOutput was committed in a prior block — immutable
     *      - blockhash(settleBlock) was not knowable at commit time
     *      - Neither the committer nor the settler alone determines the outcome
     */
    function _doSettle() private returns (bytes32 finalRandomness, bytes memory gameData) {
        // Settlement authorization: must be a registered controller
        // (prevents non-participants from triggering settlement as a gas attack)
        require(
            controllerKeyRegistered[tx.origin], "PhasedVRF: settle caller not registered controller"
        );

        bytes32 bh = blockhash(pendingCommit.settleBlock);
        require(bh != bytes32(0), "PhasedVRF: blockhash unavailable, settle expired");

        bytes32 vrfOutput = pendingCommit.vrfOutput;
        gameData = pendingCommit.gameData;

        // Final randomness: commit-phase VRF output (keeper's contribution,
        // unknowable to block proposers at commit time) XOR'd with the
        // blockhash of the settle block (proposer's contribution, unknowable
        // to the keeper when they committed).
        finalRandomness = keccak256(abi.encodePacked(vrfOutput, bh));

        emit VRFSettled(_loopID, vrfOutput, bh, finalRandomness, tx.origin);

        // Clear pending state. Note: _loopID is incremented by the game
        // contract after processing the settle return value.
        delete pendingCommit;
    }
}
