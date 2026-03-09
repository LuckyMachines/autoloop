// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/AutoLoop.sol";
import "../src/AutoLoopRegistry.sol";
import "../src/AutoLoopRegistrar.sol";
import "../examples/HybridGame.sol";

/**
 * @title HybridGameTest
 * @notice Forge test suite for the HybridGame example and AutoLoopHybridVRFCompatible base.
 *         Tests ERC-165 interface detection, shouldProgressLoop VRF flag encoding,
 *         standard tick execution, rejection paths, and multi-tick state progression.
 *
 *         VRF proof generation is off-chain (worker-side), so VRF tick execution
 *         is tested via the rejection path and VRF flag signaling. Standard ticks
 *         are tested end-to-end through AutoLoop.sol.
 */
contract HybridGameTest is Test {
    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------

    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    HybridGame public game;

    address public proxyAdmin;
    address public admin;
    address public controller1;

    bytes32 public CONTROLLER_ROLE;
    bytes32 public REGISTRAR_ROLE;

    uint256 constant GAS_PRICE = 20 gwei;
    uint256 constant INTERVAL = 10; // 10 seconds between ticks
    uint256 constant VRF_FREQUENCY = 10; // VRF every 10th tick

    receive() external payable {}

    // ---------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------

    function setUp() public {
        proxyAdmin = vm.addr(99);
        controller1 = vm.addr(0xC0);
        admin = address(this);

        vm.deal(admin, 1000 ether);
        vm.deal(controller1, 100 ether);

        // Deploy AutoLoop behind proxy
        AutoLoop autoLoopImpl = new AutoLoop();
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(string)", "0.0.1")
        );
        autoLoop = AutoLoop(address(autoLoopProxy));

        // Deploy Registry behind proxy
        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(address)", admin)
        );
        registry = AutoLoopRegistry(address(registryProxy));

        // Deploy Registrar behind proxy
        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();
        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            proxyAdmin,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(autoLoop),
                address(registry),
                admin
            )
        );
        registrar = AutoLoopRegistrar(address(registrarProxy));

        CONTROLLER_ROLE = autoLoop.CONTROLLER_ROLE();
        REGISTRAR_ROLE = autoLoop.REGISTRAR_ROLE();

        // Grant registrar roles
        registry.setRegistrar(address(registrar));
        autoLoop.setRegistrar(address(registrar));

        // Deploy HybridGame: 10s interval, VRF every 10th tick
        game = new HybridGame(INTERVAL, VRF_FREQUENCY);
        registrar.registerAutoLoopFor(address(game), 2_000_000);

        // Register controller
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        // Fund game
        registrar.deposit{value: 10 ether}(address(game));
    }

    // ===============================================================
    //  Section 1 — ERC-165 Interface Detection
    // ===============================================================

    function test_SupportsHybridVRFInterface() public view {
        bytes4 hybridId = bytes4(keccak256("AutoLoopHybridVRFCompatible"));
        assertTrue(game.supportsInterface(hybridId), "Should support hybrid VRF interface");
    }

    function test_SupportsVRFInterface() public view {
        bytes4 vrfId = bytes4(keccak256("AutoLoopVRFCompatible"));
        assertTrue(game.supportsInterface(vrfId), "Hybrid should also support full VRF interface");
    }

    function test_SupportsAutoLoopCompatibleInterface() public view {
        assertTrue(
            game.supportsInterface(type(AutoLoopCompatibleInterface).interfaceId),
            "Should support AutoLoopCompatible interface"
        );
    }

    function test_SupportsIAccessControlEnumerable() public view {
        assertTrue(
            game.supportsInterface(type(IAccessControlEnumerable).interfaceId),
            "Should support IAccessControlEnumerable"
        );
    }

    function test_SupportsERC165() public view {
        assertTrue(game.supportsInterface(0x01ffc9a7), "Should support ERC165");
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(game.supportsInterface(0xdeadbeef), "Should not support random interface");
    }

    function test_InterfaceIDsAreDistinct() public view {
        bytes4 hybridId = game.HYBRID_VRF_INTERFACE_ID();
        bytes4 vrfId = game.VRF_INTERFACE_ID();
        assertTrue(hybridId != vrfId, "Hybrid and VRF interface IDs must be different");
    }

    // ===============================================================
    //  Section 2 — Initial State
    // ===============================================================

    function test_InitialState() public view {
        assertEq(game.score(), 0, "Initial score should be 0");
        assertEq(game.totalTicks(), 0, "Initial totalTicks should be 0");
        assertEq(game.totalVRFTicks(), 0, "Initial totalVRFTicks should be 0");
        assertEq(game.interval(), INTERVAL, "Interval should match constructor");
        assertEq(game.vrfFrequency(), VRF_FREQUENCY, "VRF frequency should match constructor");
        assertEq(game.lastEventType(), 0, "Initial lastEventType should be 0");
        assertEq(game.lastEventMagnitude(), 0, "Initial lastEventMagnitude should be 0");
        assertEq(game.lastRandomness(), bytes32(0), "Initial lastRandomness should be 0");
    }

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("Interval must be > 0");
        new HybridGame(0, 10);
    }

    function test_ConstructorRejectsZeroFrequency() public {
        vm.expectRevert("VRF frequency must be > 0");
        new HybridGame(10, 0);
    }

    // ===============================================================
    //  Section 3 — shouldProgressLoop Encoding
    // ===============================================================

    function test_ShouldProgressReturnsFalseBeforeInterval() public view {
        // setUp doesn't warp, so lastTimestamp == block.timestamp
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready, "Should not be ready before interval elapses");
    }

    function test_ShouldProgressReturnsTrueAfterInterval() public {
        vm.warp(block.timestamp + INTERVAL);
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready, "Should be ready after interval elapses");
    }

    function test_ShouldProgressEncodesNonVRFFlag() public {
        // loopID starts at 1; 1 % 10 != 0 → needsVRF = false
        vm.warp(block.timestamp + INTERVAL);
        (, bytes memory data) = game.shouldProgressLoop();

        (bool needsVRF, uint256 loopID, bytes memory gameData) = abi.decode(
            data, (bool, uint256, bytes)
        );

        assertFalse(needsVRF, "Tick 1 should not need VRF");
        assertEq(loopID, 1, "Should return loopID 1");
        assertEq(gameData.length, 0, "gameData should be empty");
    }

    function test_ShouldProgressEncodesVRFFlagAtFrequency() public {
        // Advance loopID to 10 by executing 9 standard ticks
        _executeStandardTicks(9);

        // Now loopID is 10; 10 % 10 == 0 → needsVRF = true
        vm.warp(block.timestamp + INTERVAL);
        (, bytes memory data) = game.shouldProgressLoop();

        (bool needsVRF, uint256 loopID, ) = abi.decode(
            data, (bool, uint256, bytes)
        );

        assertTrue(needsVRF, "Tick 10 should need VRF");
        assertEq(loopID, 10, "Should return loopID 10");
    }

    function test_VRFFlagPatternAcross20Ticks() public {
        // Verify the VRF flag pattern for loopIDs 1-20
        // VRF should only be true at 10 and 20
        bool[] memory expectedVRF = new bool[](20);
        expectedVRF[9] = true;  // loopID 10 (index 9)
        expectedVRF[19] = true; // loopID 20 (index 19)

        for (uint256 i = 0; i < 20; i++) {
            vm.warp(block.timestamp + INTERVAL);
            (, bytes memory data) = game.shouldProgressLoop();
            (bool needsVRF, uint256 loopID, ) = abi.decode(data, (bool, uint256, bytes));

            assertEq(loopID, i + 1, "loopID should match iteration");
            assertEq(needsVRF, expectedVRF[i], string.concat(
                "VRF flag mismatch at loopID ", vm.toString(i + 1)
            ));

            // Only execute standard ticks (skip VRF ticks since we can't generate proofs)
            if (!needsVRF) {
                _executeStandardTickDirect(loopID);
            } else {
                // Can't execute VRF tick without a proof — just verify the flag was correct
                break;
            }
        }
    }

    // ===============================================================
    //  Section 4 — Standard Tick Execution (Direct)
    // ===============================================================

    function test_StandardTickIncrementsScore() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));
        game.progressLoop(data);

        assertEq(game.score(), 1, "Score should be 1 after one tick");
    }

    function test_StandardTickIncrementsTotalTicks() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));
        game.progressLoop(data);

        assertEq(game.totalTicks(), 1, "totalTicks should be 1");
    }

    function test_StandardTickDoesNotIncrementVRFTicks() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));
        game.progressLoop(data);

        assertEq(game.totalVRFTicks(), 0, "totalVRFTicks should remain 0 for standard tick");
    }

    function test_StandardTickUpdatesTimestamp() public {
        uint256 expectedTime = block.timestamp + INTERVAL;
        vm.warp(expectedTime);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));
        game.progressLoop(data);

        assertEq(game.lastTimestamp(), expectedTime, "lastTimestamp should update");
    }

    function test_StandardTickEmitsStandardTickEvent() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));

        vm.expectEmit(true, false, false, true, address(game));
        emit AutoLoopHybridVRFCompatible.StandardTick(1, block.timestamp + INTERVAL);

        game.progressLoop(data);
    }

    function test_StandardTickEmitsScoreUpdatedEvent() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));

        vm.expectEmit(true, false, false, true, address(game));
        emit HybridGame.ScoreUpdated(1, 1, block.timestamp + INTERVAL);

        game.progressLoop(data);
    }

    function test_StandardTickIncrementsLoopID() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));
        game.progressLoop(data);

        // After tick 1, shouldProgressLoop should return loopID 2
        vm.warp(block.timestamp + INTERVAL);
        (, bytes memory nextData) = game.shouldProgressLoop();
        (, uint256 nextLoopID, ) = abi.decode(nextData, (bool, uint256, bytes));
        assertEq(nextLoopID, 2, "loopID should increment to 2");
    }

    // ===============================================================
    //  Section 5 — Standard Ticks Through AutoLoop
    // ===============================================================

    function test_StandardTickThroughAutoLoop() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));

        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        autoLoop.progressLoop(address(game), data);

        assertEq(game.score(), 1, "Score should be 1 after AutoLoop tick");
        assertEq(game.totalTicks(), 1, "totalTicks should be 1");
    }

    function test_MultipleStandardTicksThroughAutoLoop() public {
        _executeStandardTicks(5);

        assertEq(game.score(), 5, "Score should be 5 after 5 ticks");
        assertEq(game.totalTicks(), 5, "totalTicks should be 5");
        assertEq(game.totalVRFTicks(), 0, "No VRF ticks should have occurred");
    }

    function test_NineStandardTicksThenVRFSignal() public {
        // Execute 9 standard ticks through AutoLoop
        _executeStandardTicks(9);

        assertEq(game.score(), 9, "Score should be 9 after 9 standard ticks");

        // Now tick 10 should signal VRF
        vm.warp(block.timestamp + INTERVAL);
        (bool ready, bytes memory pollData) = game.shouldProgressLoop();
        assertTrue(ready, "Should be ready for tick 10");

        (bool needsVRF, uint256 loopID, ) = abi.decode(pollData, (bool, uint256, bytes));
        assertTrue(needsVRF, "Tick 10 must signal VRF");
        assertEq(loopID, 10, "loopID should be 10");
    }

    // ===============================================================
    //  Section 6 — Rejection Paths
    // ===============================================================

    function test_RejectsVRFRequiredWithoutProof() public {
        // Advance to loopID 10 (which needs VRF)
        _executeStandardTicks(9);

        // Try to send a standard tick with needsVRF=true but no VRF envelope
        // Data length < 640, so it goes through the standard path which requires !needsVRF
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(true, uint256(10), bytes(""));

        vm.expectRevert("VRF required but no proof provided");
        game.progressLoop(data);
    }

    function test_RejectsStaleLoopID() public {
        vm.warp(block.timestamp + INTERVAL);

        // Send wrong loopID (2 instead of 1)
        bytes memory data = abi.encode(false, uint256(2), bytes(""));

        vm.expectRevert("Stale loop ID");
        game.progressLoop(data);
    }

    function test_RejectsStaleLoopIDThroughAutoLoop() public {
        vm.warp(block.timestamp + INTERVAL);

        // Send wrong loopID through AutoLoop
        bytes memory data = abi.encode(false, uint256(999), bytes(""));

        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        // AutoLoop wraps the revert
        vm.expectRevert("Unable to progress loop. Call not a success");
        autoLoop.progressLoop(address(game), data);
    }

    function test_RejectsVRFRequiredThroughAutoLoop() public {
        // Advance to loopID 10
        _executeStandardTicks(9);

        vm.warp(block.timestamp + INTERVAL);
        vm.roll(block.number + 1);
        bytes memory data = abi.encode(true, uint256(10), bytes(""));

        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        vm.expectRevert("Unable to progress loop. Call not a success");
        autoLoop.progressLoop(address(game), data);
    }

    // ===============================================================
    //  Section 7 — Multi-Tick State Verification
    // ===============================================================

    function test_ScoreAccumulatesCorrectly() public {
        // Run 9 standard ticks, each adds 1
        _executeStandardTicks(9);

        assertEq(game.score(), 9, "Score should accumulate to 9");
        assertEq(game.totalTicks(), 9, "9 ticks should have executed");
    }

    function test_LoopIDProgressesCorrectly() public {
        _executeStandardTicks(5);

        vm.warp(block.timestamp + INTERVAL);
        (, bytes memory data) = game.shouldProgressLoop();
        (, uint256 loopID, ) = abi.decode(data, (bool, uint256, bytes));
        assertEq(loopID, 6, "loopID should be 6 after 5 ticks");
    }

    function test_VRFNeverRequestedBeforeTick10() public {
        // Check each tick 1-9 signals no VRF
        for (uint256 i = 1; i <= 9; i++) {
            vm.warp(block.timestamp + INTERVAL);
            (, bytes memory data) = game.shouldProgressLoop();
            (bool needsVRF, , ) = abi.decode(data, (bool, uint256, bytes));
            assertFalse(needsVRF, string.concat("Tick ", vm.toString(i), " should not need VRF"));

            _executeStandardTickDirect(i);
        }
    }

    // ===============================================================
    //  Section 8 — Gas Comparison (Standard vs VRF Signal)
    // ===============================================================

    function test_StandardTickGasIsReasonable() public {
        vm.warp(block.timestamp + INTERVAL);
        bytes memory data = abi.encode(false, uint256(1), bytes(""));

        uint256 gasBefore = gasleft();
        game.progressLoop(data);
        uint256 gasUsed = gasBefore - gasleft();

        // Standard tick should be cheap — well under 100k gas
        assertLt(gasUsed, 100_000, "Standard tick should use less than 100k gas");
    }

    // ===============================================================
    //  Section 9 — VRF Frequency Variants
    // ===============================================================

    function test_VRFEveryTick() public {
        // Deploy with vrfFrequency=1 — every tick needs VRF
        HybridGame everyTickGame = new HybridGame(INTERVAL, 1);

        vm.warp(block.timestamp + INTERVAL);
        (, bytes memory data) = everyTickGame.shouldProgressLoop();
        (bool needsVRF, , ) = abi.decode(data, (bool, uint256, bytes));
        // loopID=1, 1%1==0 → true
        assertTrue(needsVRF, "Every tick should need VRF with frequency=1");
    }

    function test_VRFEvery5thTick() public {
        HybridGame freq5Game = new HybridGame(INTERVAL, 5);

        // Tick 1-4: no VRF
        for (uint256 i = 1; i <= 4; i++) {
            vm.warp(block.timestamp + INTERVAL);
            (, bytes memory data) = freq5Game.shouldProgressLoop();
            (bool needsVRF, , ) = abi.decode(data, (bool, uint256, bytes));
            assertFalse(needsVRF, "Non-5th tick should not need VRF");

            bytes memory tickData = abi.encode(false, i, bytes(""));
            freq5Game.progressLoop(tickData);
        }

        // Tick 5: VRF
        vm.warp(block.timestamp + INTERVAL);
        (, bytes memory data5) = freq5Game.shouldProgressLoop();
        (bool needsVRF5, uint256 loopID5, ) = abi.decode(data5, (bool, uint256, bytes));
        assertTrue(needsVRF5, "5th tick should need VRF");
        assertEq(loopID5, 5, "loopID should be 5");
    }

    // ===============================================================
    //  Internal Helpers
    // ===============================================================

    /**
     * @dev Execute N standard ticks through AutoLoop, advancing time and block for each.
     *      Uses explicit timestamps/blocks to avoid VIA_IR caching of block globals.
     *      Only works for ticks that don't need VRF (loopID % vrfFrequency != 0).
     */
    function _executeStandardTicks(uint256 count) internal {
        // Read block globals ONCE before the loop to establish baseline
        uint256 ts = block.timestamp;
        uint256 bn = block.number;

        for (uint256 i = 1; i <= count; i++) {
            ts += INTERVAL;
            bn += 1;
            vm.warp(ts);
            vm.roll(bn);
            bytes memory data = abi.encode(false, i, bytes(""));

            vm.txGasPrice(GAS_PRICE);
            vm.prank(controller1);
            autoLoop.progressLoop(address(game), data);
        }
    }

    /**
     * @dev Execute a single standard tick by calling progressLoop directly (no AutoLoop).
     *      Caller must ensure time has been advanced via vm.warp before calling.
     */
    function _executeStandardTickDirect(uint256 loopID) internal {
        bytes memory data = abi.encode(false, loopID, bytes(""));
        game.progressLoop(data);
    }
}
