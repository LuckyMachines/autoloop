// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/AutoLoop.sol";
import "../src/AutoLoopRegistry.sol";
import "../src/AutoLoopRegistrar.sol";
import "../src/VRFVerifier.sol";
import "../src/sample/RandomGame.sol";

/**
 * @title AutoLoopVRFTest
 * @notice Foundry test suite for AutoLoop native VRF.
 *         Tests VRF verification, integration with RandomGame, and security properties.
 */
contract AutoLoopVRFTest is Test {
    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------

    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    RandomGame public game;

    address public proxyAdmin;
    address public admin;
    address public controller1;
    uint256 public controller1PrivKey;

    bytes32 public CONTROLLER_ROLE;
    bytes32 public REGISTRAR_ROLE;

    uint256 constant GAS_PRICE = 20 gwei;

    // secp256k1 generator point
    uint256 constant GX =
        0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798;
    uint256 constant GY =
        0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8;
    uint256 constant PP =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 constant NN =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    receive() external payable {}

    // ---------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------

    function setUp() public {
        proxyAdmin = vm.addr(99);
        controller1PrivKey = 0xABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789;
        controller1 = vm.addr(controller1PrivKey);
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

        // Deploy RandomGame with 0 interval
        game = new RandomGame(0);
        registrar.registerAutoLoopFor(address(game), 2_000_000);

        // Register controller
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        // Fund game
        registrar.deposit{value: 10 ether}(address(game));

        // Advance time so shouldProgressLoop returns true
        vm.warp(block.timestamp + 1);
    }

    // ===============================================================
    //  Section 1 — VRF Library Unit Tests
    // ===============================================================

    function test_HashToCurveProducesValidPoint() public view {
        uint256[2] memory pk = _getController1PublicKey();
        bytes memory message = abi.encodePacked(keccak256(abi.encodePacked(address(game), uint256(1))));

        (uint256 hx, uint256 hy) = VRFVerifier.hashToCurve(pk, message);

        // Point must be on secp256k1
        uint256 lhs = mulmod(hy, hy, PP);
        uint256 rhs = addmod(mulmod(mulmod(hx, hx, PP), hx, PP), 7, PP);
        assertEq(lhs, rhs, "Hash-to-curve point must be on secp256k1");
    }

    function test_HashToCurveIsDeterministic() public view {
        uint256[2] memory pk = _getController1PublicKey();
        bytes memory message = abi.encodePacked(keccak256(abi.encodePacked(address(game), uint256(1))));

        (uint256 hx1, uint256 hy1) = VRFVerifier.hashToCurve(pk, message);
        (uint256 hx2, uint256 hy2) = VRFVerifier.hashToCurve(pk, message);

        assertEq(hx1, hx2, "Hash-to-curve must be deterministic (x)");
        assertEq(hy1, hy2, "Hash-to-curve must be deterministic (y)");
    }

    function test_DifferentMessagesDifferentPoints() public view {
        uint256[2] memory pk = _getController1PublicKey();
        bytes memory msg1 = abi.encodePacked(keccak256(abi.encodePacked(address(game), uint256(1))));
        bytes memory msg2 = abi.encodePacked(keccak256(abi.encodePacked(address(game), uint256(2))));

        (uint256 hx1, ) = VRFVerifier.hashToCurve(pk, msg1);
        (uint256 hx2, ) = VRFVerifier.hashToCurve(pk, msg2);

        assertTrue(hx1 != hx2, "Different messages should produce different points");
    }

    function test_GammaToHashIsDeterministic() public pure {
        bytes32 h1 = VRFVerifier.gammaToHash(GX, GY);
        bytes32 h2 = VRFVerifier.gammaToHash(GX, GY);
        assertEq(h1, h2, "gammaToHash must be deterministic");
    }

    function test_GammaToHashDifferentInputsDifferentOutputs() public pure {
        bytes32 h1 = VRFVerifier.gammaToHash(GX, GY);
        // Use a doubled generator point for different input
        bytes32 h2 = VRFVerifier.gammaToHash(
            0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5,
            0x1AE168FEA63DC339A3C58419466CEAE1032688D15F9C819A21C56BFC4DE05C36
        );
        assertTrue(h1 != h2, "Different gamma points should produce different hashes");
    }

    function test_EcAddIdentity() public pure {
        // P + O = P (where O is the point at infinity represented as (0,0))
        (uint256 rx, uint256 ry) = VRFVerifier.ecAdd(GX, GY, 0, 0);
        assertEq(rx, GX, "G + O should equal G (x)");
        assertEq(ry, GY, "G + O should equal G (y)");
    }

    function test_EcSubSamePoint() public pure {
        // P - P = O (point at infinity)
        (uint256 rx, uint256 ry) = VRFVerifier.ecSub(GX, GY, GX, GY);
        assertEq(rx, 0, "G - G should be point at infinity (x)");
        assertEq(ry, 0, "G - G should be point at infinity (y)");
    }

    // ===============================================================
    //  Section 2 — AutoLoopVRFCompatible Contract Tests
    // ===============================================================

    function test_RandomGameSupportsVRFInterface() public view {
        bytes4 vrfInterfaceId = bytes4(keccak256("AutoLoopVRFCompatible"));
        assertTrue(game.supportsInterface(vrfInterfaceId), "Should support VRF interface");
    }

    function test_RandomGameSupportsAutoLoopInterface() public view {
        assertTrue(
            game.supportsInterface(type(AutoLoopCompatibleInterface).interfaceId),
            "Should support AutoLoopCompatible interface"
        );
    }

    function test_RegisterControllerKey() public {
        uint256[2] memory pk = _getController1PublicKey();

        vm.prank(controller1);
        game.registerControllerKey(controller1, pk[0], pk[1]);

        assertTrue(game.controllerKeyRegistered(controller1), "Controller key should be registered");
    }

    function test_AdminCanRegisterControllerKey() public {
        uint256[2] memory pk = _getController1PublicKey();

        // Admin registers key for controller
        game.registerControllerKey(controller1, pk[0], pk[1]);

        assertTrue(game.controllerKeyRegistered(controller1), "Controller key should be registered by admin");
    }

    function test_NonControllerNonAdminCannotRegisterKey() public {
        uint256[2] memory pk = _getController1PublicKey();
        address random = vm.addr(42);

        vm.prank(random);
        vm.expectRevert("Only controller or admin can register key");
        game.registerControllerKey(controller1, pk[0], pk[1]);
    }

    function test_RejectsInvalidPublicKey() public {
        vm.prank(controller1);
        vm.expectRevert("Invalid public key");
        game.registerControllerKey(controller1, 1, 2); // Not on curve
    }

    function test_RejectsZeroPublicKey() public {
        vm.prank(controller1);
        vm.expectRevert("Invalid public key");
        game.registerControllerKey(controller1, 0, 0);
    }

    function test_ComputeSeedIsDeterministic() public view {
        bytes memory seed1 = game.computeSeed(1);
        bytes memory seed2 = game.computeSeed(1);
        assertEq(keccak256(seed1), keccak256(seed2), "Seeds should be deterministic");
    }

    function test_ComputeSeedDiffersByLoopID() public view {
        bytes memory seed1 = game.computeSeed(1);
        bytes memory seed2 = game.computeSeed(2);
        assertTrue(
            keccak256(seed1) != keccak256(seed2),
            "Different loop IDs should produce different seeds"
        );
    }

    function test_ShouldProgressLoopReturnsTrue() public view {
        (bool loopIsReady, ) = game.shouldProgressLoop();
        assertTrue(loopIsReady, "Should be ready after interval");
    }

    function test_ShouldProgressLoopReturnsLoopID() public view {
        (, bytes memory data) = game.shouldProgressLoop();
        uint256 loopID = abi.decode(data, (uint256));
        assertEq(loopID, 1, "Should return initial loopID of 1");
    }

    // ===============================================================
    //  Section 3 — VRF Proof Rejection Tests
    // ===============================================================

    function test_RejectsUnregisteredController() public {
        // Try to progress without registering controller key
        (bool loopIsReady, bytes memory gameData) = game.shouldProgressLoop();
        assertTrue(loopIsReady);

        // Construct fake VRF envelope
        bytes memory vrfEnvelope = abi.encode(
            uint8(1), // vrfVersion
            [uint256(1), uint256(2), uint256(3), uint256(4)], // fake proof
            [uint256(1), uint256(2)], // fake uPoint
            [uint256(1), uint256(2), uint256(3), uint256(4)], // fake vComponents
            gameData
        );

        // AutoLoop.sol uses low-level .call() so inner reverts surface as
        // "Unable to progress loop. Call not a success"
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        vm.expectRevert("Unable to progress loop. Call not a success");
        autoLoop.progressLoop(address(game), vrfEnvelope);
    }

    function test_RejectsWrongVRFVersion() public {
        uint256[2] memory pk = _getController1PublicKey();
        game.registerControllerKey(controller1, pk[0], pk[1]);

        (, bytes memory gameData) = game.shouldProgressLoop();

        // Construct envelope with wrong version
        bytes memory vrfEnvelope = abi.encode(
            uint8(99), // wrong version
            [uint256(GX), GY, uint256(1), uint256(1)],
            [uint256(GX), GY],
            [uint256(GX), GY, GX, GY],
            gameData
        );

        // AutoLoop.sol uses low-level .call() so inner reverts surface as
        // "Unable to progress loop. Call not a success"
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        vm.expectRevert("Unable to progress loop. Call not a success");
        autoLoop.progressLoop(address(game), vrfEnvelope);
    }

    // ===============================================================
    //  Section 4 — RandomGame State Tests
    // ===============================================================

    function test_InitialState() public view {
        assertEq(game.lastRoll(), 0, "Initial roll should be 0");
        assertEq(game.totalRolls(), 0, "Initial total rolls should be 0");
        assertEq(game.interval(), 0, "Interval should be 0");
    }

    function test_VRFVersionConstant() public view {
        assertEq(game.VRF_VERSION(), 1, "VRF version should be 1");
    }

    // ===============================================================
    //  Section 5 — Gas Budget Validation
    // ===============================================================

    function test_HashToCurveGasBudget() public view {
        uint256[2] memory pk = _getController1PublicKey();
        bytes memory message = abi.encodePacked(keccak256(abi.encodePacked(address(game), uint256(1))));

        uint256 gasBefore = gasleft();
        VRFVerifier.hashToCurve(pk, message);
        uint256 gasUsed = gasBefore - gasleft();

        // hashToCurve should use less than 250k gas (pure Solidity EC math)
        assertLt(gasUsed, 250_000, "hashToCurve should use less than 250k gas");
    }

    function test_GammaToHashGasBudget() public view {
        uint256 gasBefore = gasleft();
        VRFVerifier.gammaToHash(GX, GY);
        uint256 gasUsed = gasBefore - gasleft();

        // gammaToHash is just a keccak256, should be very cheap
        assertLt(gasUsed, 1_000, "gammaToHash should use less than 1k gas");
    }

    function test_EcAddGasBudget() public view {
        // Use 2G for the second point
        uint256 x2 = 0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5;
        uint256 y2 = 0x1AE168FEA63DC339A3C58419466CEAE1032688D15F9C819A21C56BFC4DE05C36;

        uint256 gasBefore = gasleft();
        VRFVerifier.ecAdd(GX, GY, x2, y2);
        uint256 gasUsed = gasBefore - gasleft();

        // EC addition should use less than 60k gas (pure Solidity modular arithmetic)
        assertLt(gasUsed, 60_000, "ecAdd should use less than 60k gas");
    }

    // ===============================================================
    //  Section 6 — ERC165 Interface Detection
    // ===============================================================

    function test_SupportsIAccessControlEnumerable() public view {
        assertTrue(
            game.supportsInterface(type(IAccessControlEnumerable).interfaceId),
            "Should support IAccessControlEnumerable"
        );
    }

    function test_SupportsERC165() public view {
        // ERC165 interface ID is 0x01ffc9a7
        assertTrue(
            game.supportsInterface(0x01ffc9a7),
            "Should support ERC165"
        );
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(
            game.supportsInterface(0xdeadbeef),
            "Should not support random interface"
        );
    }

    // ===============================================================
    //  Internal helpers
    // ===============================================================

    /**
     * @dev Derive the public key for controller1 from its known private key.
     *      For testing, we use the generator point multiplied by the private key.
     *      Since we can't do EC scalar multiplication easily in Solidity tests,
     *      we use vm.addr() to get the address and manually set a known key pair.
     *
     *      For these tests, we use a well-known test keypair.
     */
    function _getController1PublicKey() internal pure returns (uint256[2] memory pk) {
        // For testing purposes, use the secp256k1 generator point as a "public key"
        // This is a valid point on the curve. In production, this would be derived
        // from the controller's actual private key.
        pk[0] = GX;
        pk[1] = GY;
    }
}
