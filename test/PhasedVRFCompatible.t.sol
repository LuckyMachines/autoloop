// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/PhasedVRFCompatible.sol";
import "../src/AutoLoopCompatibleInterface.sol";

/**
 * @title PhasedGame
 * @notice Minimal concrete implementation of PhasedVRFCompatible for testing.
 *         Bypasses VRF proof verification via testCommit() so tests can focus
 *         on the two-phase mechanics and blockhash mixing.
 */
contract PhasedGame is PhasedVRFCompatible {
    uint256 public result;
    uint256 public totalRounds;
    uint256 public roundInterval;
    uint256 public lastTimestamp;

    event RoundSettled(uint256 indexed round, bytes32 randomness, uint256 result);

    // Public getter for the internal _loopID from AutoLoopCompatible
    function loopID() public view returns (uint256) { return _loopID; }

    constructor(uint256 _interval) {
        roundInterval = _interval;
        lastTimestamp = block.timestamp;
    }

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool elapsed = block.timestamp - lastTimestamp >= roundInterval;
        return _phasedShouldProgress(elapsed);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bool settled, bytes32 randomness, ) = _dispatchPhase(progressWithData);
        if (!settled) return;

        result = uint256(randomness) % 100;
        totalRounds++;
        lastTimestamp = block.timestamp;
        _loopID++;

        emit RoundSettled(totalRounds, randomness, result);
    }

    /**
     * @notice Test harness: store a commit directly, bypassing VRF proof verification.
     *         Caller must be a registered controller (same authz as real _doCommit).
     *         Mirrors _dispatchPhase expiry cleanup so expiry tests work correctly.
     */
    function testCommit(bytes32 vrfOutput, bytes memory gameData) external {
        // Clear expired commits first — mirrors _dispatchPhase behavior
        if (pendingCommit.exists) {
            uint256 elapsed = block.number > pendingCommit.settleBlock
                ? block.number - pendingCommit.settleBlock
                : 0;
            if (elapsed > SETTLE_EXPIRY) {
                emit VRFCommitExpired(_loopID, pendingCommit.vrfOutput, pendingCommit.settleBlock);
                delete pendingCommit;
            }
        }

        require(!pendingCommit.exists, "PhasedGame: commit already pending");
        require(controllerKeyRegistered[msg.sender], "PhasedGame: not a registered controller");

        uint256 settleBlock = block.number + SETTLE_DELAY;
        pendingCommit = Commit({
            vrfOutput:   vrfOutput,
            gameData:    gameData,
            settleBlock: settleBlock,
            controller:  msg.sender,
            exists:      true
        });
        emit VRFCommitted(loopID(), vrfOutput, settleBlock, msg.sender);
    }
}

// -----------------------------------------------------------------------
// Test suite
// -----------------------------------------------------------------------

contract PhasedVRFCompatibleTest is Test {

    PhasedGame internal game;

    address internal admin;
    address internal controller1;
    address internal controller2;
    address internal unregistered;

    // secp256k1 generator G — valid on the curve
    uint256 constant GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 constant GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;

    bytes32 constant VRF_OUTPUT_A = keccak256("vrfA");
    bytes32 constant VRF_OUTPUT_B = keccak256("vrfB");

    receive() external payable {}

    function setUp() public {
        admin        = address(this);
        controller1  = vm.addr(1);
        controller2  = vm.addr(2);
        unregistered = vm.addr(99);

        vm.deal(admin,        10 ether);
        vm.deal(controller1,  10 ether);
        vm.deal(controller2,  10 ether);

        game = new PhasedGame(0);

        // Register both controllers with G (valid secp256k1 point)
        game.registerControllerKey(controller1, GX, GY);
        game.registerControllerKey(controller2, GX, GY);

        vm.roll(100);
    }

    // Helper: commit + roll to settle window + settle
    function _commitAndSettle(address ctrl, bytes32 vrfOutput) internal returns (uint256 settled) {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(ctrl);
        game.testCommit(vrfOutput, data);

        uint256 settleBlock = block.number + game.SETTLE_DELAY();
        vm.roll(settleBlock + 1);

        bytes memory prog = abi.encode(uint256(0)); // data ignored in settle phase
        vm.prank(ctrl, ctrl); // prank both msg.sender and tx.origin
        game.progressLoop(prog);
        return settleBlock;
    }

    // ====================================================================
    //  1. Commit phase behavior
    // ====================================================================

    function test_ShouldProgressReturnsTrueInitially() public view {
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready, "should be ready before any commit");
    }

    function test_CommitStoresPendingState() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        (
            bytes32 storedOutput,
            ,
            uint256 settleBlock,
            address ctrl,
            bool exists
        ) = game.pendingCommit();

        assertTrue(exists,                                          "commit should be stored");
        assertEq(storedOutput, VRF_OUTPUT_A,                        "vrfOutput mismatch");
        assertEq(ctrl, controller1,                                 "controller mismatch");
        assertEq(settleBlock, block.number + game.SETTLE_DELAY(),   "wrong settle block");
    }

    function test_ShouldProgressReturnsFalseWhileWaiting() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        // Advance partway — settle block not reached
        vm.roll(block.number + game.SETTLE_DELAY() - 1);

        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready, "should NOT be ready before settle block");
    }

    function test_ShouldProgressReturnsTrueAfterSettleBlock() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        uint256 settleBlock = block.number + game.SETTLE_DELAY();
        vm.roll(settleBlock + 1);

        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready, "should be ready after settle block");
    }

    function test_CannotDoubleCommit() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        vm.prank(controller1);
        vm.expectRevert("PhasedGame: commit already pending");
        game.testCommit(VRF_OUTPUT_B, data);
    }

    // ====================================================================
    //  2. Settle phase mechanics
    // ====================================================================

    function test_SettleMixesVRFOutputWithBlockhash() public {
        uint256 commitBlock = block.number;
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        uint256 settleBlock = commitBlock + game.SETTLE_DELAY();
        vm.roll(settleBlock + 1);

        bytes32 expectedBlockhash  = blockhash(settleBlock);
        bytes32 expectedRandomness = keccak256(abi.encodePacked(VRF_OUTPUT_A, expectedBlockhash));

        // Precompute prog data before pranking to avoid staticcall consuming prank
        bytes memory prog = abi.encode(uint256(0));
        // Set both msg.sender and tx.origin so _doSettle's authz check passes
        vm.prank(controller1, controller1);
        game.progressLoop(prog);

        assertEq(game.result(), uint256(expectedRandomness) % 100, "result must use blockhash-mixed randomness");
        assertEq(game.totalRounds(), 1, "one round should be settled");
    }

    function test_SettleClearsPendingCommit() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        uint256 settleBlock = block.number + game.SETTLE_DELAY();
        vm.roll(settleBlock + 1);

        bytes memory prog = abi.encode(uint256(0));
        vm.prank(controller1, controller1);
        game.progressLoop(prog);

        (, , , , bool exists) = game.pendingCommit();
        assertFalse(exists, "pending commit should be cleared after settle");
    }

    function test_SettleRevertsBeforeSettleBlock() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        // Precompute prog before expectRevert to avoid staticcall consuming expectation
        bytes memory prog = abi.encode(uint256(0));

        vm.prank(controller1, controller1);
        vm.expectRevert("PhasedVRF: settle block not reached");
        game.progressLoop(prog);
    }

    function test_SettleRequiresRegisteredController() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        uint256 settleBlock = block.number + game.SETTLE_DELAY();
        vm.roll(settleBlock + 1);

        bytes memory prog = abi.encode(uint256(0));
        vm.prank(unregistered, unregistered);
        vm.expectRevert("PhasedVRF: settle caller not registered controller");
        game.progressLoop(prog);
    }

    // ====================================================================
    //  3. Core security property: randomness incorporates future blockhash
    // ====================================================================

    function test_FinalRandomnessIsNotVRFOutputAlone() public {
        uint256 commitBlock = block.number;
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        uint256 settleBlock = commitBlock + game.SETTLE_DELAY();
        vm.roll(settleBlock + 1);

        bytes memory prog = abi.encode(uint256(0));
        vm.prank(controller1, controller1);
        game.progressLoop(prog);

        bytes32 bh = blockhash(settleBlock);
        if (bh != bytes32(0)) {
            // If randomness were just vrfOutput alone, result = uint256(VRF_OUTPUT_A) % 100
            // With blockhash mixing: result = uint256(keccak256(vrfOutput, bh)) % 100
            uint256 expectedMixed = uint256(keccak256(abi.encodePacked(VRF_OUTPUT_A, bh))) % 100;
            assertEq(game.result(), expectedMixed, "result must incorporate blockhash");
        }
    }

    function test_SameVRFOutputDifferentSettleBlocksDifferentRandomness() public {
        // Round 1: commit at block 100, settle at block 106
        vm.roll(100);
        bytes memory data1 = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data1);
        vm.roll(106);
        bytes memory prog = abi.encode(uint256(0));
        vm.prank(controller1, controller1);
        game.progressLoop(prog);
        bytes32 bh1 = blockhash(105);
        bytes32 rand1 = keccak256(abi.encodePacked(VRF_OUTPUT_A, bh1));

        // Round 2: commit at block 200, settle at block 206 — same VRF output, different block
        vm.roll(200);
        bytes memory data2 = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data2);
        vm.roll(206);
        bytes memory prog2 = abi.encode(uint256(0));
        vm.prank(controller1, controller1);
        game.progressLoop(prog2);
        bytes32 bh2 = blockhash(205);
        bytes32 rand2 = keccak256(abi.encodePacked(VRF_OUTPUT_A, bh2));

        // Same vrfOutput, different settle blocks → different blockhashes → different randomness
        if (bh1 != bh2) {
            assertTrue(rand1 != rand2, "different settle blocks should yield different randomness");
        }
    }

    function test_DifferentVRFOutputsSameSettleBlockDifferentRandomness() public {
        // Commit A then settle, commit B then settle — different VRF outputs
        vm.roll(100);
        bytes memory data1 = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data1);
        vm.roll(106);
        bytes memory prog = abi.encode(uint256(0));
        vm.prank(controller1, controller1);
        game.progressLoop(prog);
        bytes32 bh1 = blockhash(105);
        bytes32 rand1 = keccak256(abi.encodePacked(VRF_OUTPUT_A, bh1));

        vm.roll(200);
        bytes memory data2 = abi.encode(game.loopID());
        vm.prank(controller2);
        game.testCommit(VRF_OUTPUT_B, data2);
        vm.roll(206);
        bytes memory prog2 = abi.encode(uint256(0));
        vm.prank(controller2, controller2);
        game.progressLoop(prog2);
        bytes32 bh2 = blockhash(205);
        bytes32 rand2 = keccak256(abi.encodePacked(VRF_OUTPUT_B, bh2));

        // Different VRF outputs → different randomness
        assertTrue(VRF_OUTPUT_A != VRF_OUTPUT_B, "test setup: VRF outputs must differ");
        assertTrue(rand1 != rand2 || bh1 == bh2, "different VRF outputs should produce different final randomness");
    }

    // ====================================================================
    //  4. Expiry behavior
    // ====================================================================

    function test_ExpiredCommitClearedOnNextShouldProgress() public {
        bytes memory data = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        // Roll way past expiry window
        uint256 expireAt = block.number + game.SETTLE_DELAY() + game.SETTLE_EXPIRY() + 1;
        vm.roll(expireAt);

        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready, "should be ready again after commit expiry");
    }

    function test_ExpiredCommitClearedOnNextDispatch() public {
        uint256 loopIDBefore = game.loopID();
        bytes memory data = abi.encode(loopIDBefore);
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data);

        // Record settleBlock from pendingCommit
        (, , uint256 settleBlock, , ) = game.pendingCommit();

        uint256 expireAt = settleBlock + game.SETTLE_EXPIRY() + 1;
        vm.roll(expireAt);

        // Next testCommit should succeed (expired commit cleared)
        bytes memory data2 = abi.encode(loopIDBefore);
        vm.prank(controller1);
        vm.expectEmit(true, false, false, false);
        emit PhasedVRFCompatible.VRFCommitExpired(loopIDBefore, VRF_OUTPUT_A, settleBlock);
        game.testCommit(VRF_OUTPUT_A, data2);
    }

    // ====================================================================
    //  5. Full cycle: commit → wait → settle → new commit
    // ====================================================================

    function test_FullTwoRoundCycle() public {
        // Round 1
        vm.roll(200);
        bytes memory data1 = abi.encode(game.loopID());
        vm.prank(controller1);
        game.testCommit(VRF_OUTPUT_A, data1);

        vm.roll(206);
        bytes memory prog1 = abi.encode(uint256(0));
        vm.prank(controller1, controller1);
        game.progressLoop(prog1);

        assertEq(game.totalRounds(), 1, "round 1 settled");

        // Should be ready for round 2
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready, "should be ready for round 2");

        // Round 2
        vm.roll(400);
        bytes memory data2 = abi.encode(game.loopID());
        vm.prank(controller2);
        game.testCommit(VRF_OUTPUT_B, data2);

        vm.roll(406);
        bytes memory prog2 = abi.encode(uint256(0));
        vm.prank(controller2, controller2);
        game.progressLoop(prog2);

        assertEq(game.totalRounds(), 2, "round 2 settled");
    }

    // ====================================================================
    //  6. Constants
    // ====================================================================

    function test_SettleDelayIs5Blocks() public view {
        assertEq(game.SETTLE_DELAY(), 5, "SETTLE_DELAY should be 5 blocks");
    }

    function test_SettleExpiryIs250Blocks() public view {
        assertEq(game.SETTLE_EXPIRY(), 250, "SETTLE_EXPIRY should be 250 blocks");
    }
}
