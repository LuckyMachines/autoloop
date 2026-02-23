// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "./AutoLoopCompatible.sol";
import "./VRFVerifier.sol";

/**
 * @title AutoLoopVRFCompatible
 * @notice Abstract base for AutoLoop-compatible contracts that require verifiable randomness.
 * @dev Extends AutoLoopCompatible. Controllers generate ECVRF proofs off-chain and wrap them
 *      around the original progressWithData. This contract verifies the proof on-chain and
 *      exposes the VRF output as a bytes32 random value.
 *
 *      progressWithData encoding (VRF envelope):
 *        abi.encode(
 *            uint8 vrfVersion,       // 1 = ECVRF-SECP256K1-SHA256-TAI
 *            uint256[4] proof,       // [gamma_x, gamma_y, c, s]
 *            uint256[2] uPoint,      // precomputed for fastVerify
 *            uint256[4] vComponents, // precomputed for fastVerify
 *            bytes gameData          // original progressWithData from shouldProgressLoop
 *        )
 *
 *      No changes to AutoLoop.sol are required. VRF is opt-in at the compatible contract level.
 */
abstract contract AutoLoopVRFCompatible is AutoLoopCompatible {
    using VRFVerifier for *;

    /// @notice VRF version constant
    uint8 public constant VRF_VERSION = 1; // ECVRF-SECP256K1-SHA256-TAI

    /// @notice ERC165 interface ID for VRF-compatible contracts
    bytes4 public constant VRF_INTERFACE_ID = bytes4(keccak256("AutoLoopVRFCompatible"));

    /// @notice Controller address => public key [x, y]
    mapping(address => uint256[2]) public controllerPublicKeys;

    /// @notice Tracks which controllers have registered public keys
    mapping(address => bool) public controllerKeyRegistered;

    /// @notice Emitted when a controller registers their VRF public key
    event ControllerKeyRegistered(address indexed controller, uint256 pkX, uint256 pkY);

    /// @notice Emitted when VRF randomness is verified and consumed
    event VRFRandomnessVerified(
        uint256 indexed loopID,
        bytes32 randomness,
        address indexed controller
    );

    /**
     * @notice Register a controller's public key for VRF proof verification.
     * @dev The public key must correspond to the controller's secp256k1 private key.
     *      Anyone can register a key for themselves. Admin can register for others.
     * @param controller The controller address.
     * @param pkX The x-coordinate of the public key.
     * @param pkY The y-coordinate of the public key.
     */
    function registerControllerKey(
        address controller,
        uint256 pkX,
        uint256 pkY
    ) external {
        require(
            _msgSender() == controller ||
                hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Only controller or admin can register key"
        );
        require(_isValidPublicKey(pkX, pkY), "Invalid public key");

        controllerPublicKeys[controller] = [pkX, pkY];
        controllerKeyRegistered[controller] = true;
        emit ControllerKeyRegistered(controller, pkX, pkY);
    }

    /**
     * @notice Compute the deterministic seed for a given loop ID.
     * @dev Seed = keccak256(address(this), loopID). Controller cannot choose seeds.
     * @param loopID The loop iteration number.
     * @return The seed bytes.
     */
    function computeSeed(uint256 loopID) public view returns (bytes memory) {
        return abi.encodePacked(keccak256(abi.encodePacked(address(this), loopID)));
    }

    /**
     * @notice Verify VRF proof and extract randomness from progressWithData.
     * @dev Called by the implementing contract's progressLoop().
     * @param progressWithData The VRF-wrapped data from the controller.
     * @param controller The controller address (tx.origin or passed from AutoLoop).
     * @return randomness The verified random bytes32 value.
     * @return gameData The original game-specific data extracted from the envelope.
     */
    function _verifyAndExtractRandomness(
        bytes calldata progressWithData,
        address controller
    ) internal returns (bytes32 randomness, bytes memory gameData) {
        (
            uint8 vrfVersion,
            uint256[4] memory proof,
            uint256[2] memory uPoint,
            uint256[4] memory vComponents,
            bytes memory innerGameData
        ) = _decodeVRFData(progressWithData);

        require(vrfVersion == VRF_VERSION, "Unsupported VRF version");
        require(controllerKeyRegistered[controller], "Controller key not registered");

        uint256[2] memory publicKey = controllerPublicKeys[controller];

        // Compute the deterministic seed for this loop ID
        bytes memory seed = computeSeed(_loopID);

        // Verify the ECVRF proof
        bool valid = VRFVerifier.fastVerify(publicKey, proof, seed, uPoint, vComponents);
        require(valid, "VRF proof verification failed");

        // Derive the random output from the verified gamma point
        randomness = VRFVerifier.gammaToHash(proof[0], proof[1]);

        emit VRFRandomnessVerified(_loopID, randomness, controller);

        return (randomness, innerGameData);
    }

    /**
     * @notice Decode the VRF envelope from progressWithData.
     * @param progressWithData The encoded VRF data.
     */
    function _decodeVRFData(
        bytes calldata progressWithData
    )
        internal
        pure
        returns (
            uint8 vrfVersion,
            uint256[4] memory proof,
            uint256[2] memory uPoint,
            uint256[4] memory vComponents,
            bytes memory gameData
        )
    {
        (vrfVersion, proof, uPoint, vComponents, gameData) = abi.decode(
            progressWithData,
            (uint8, uint256[4], uint256[2], uint256[4], bytes)
        );
    }

    /**
     * @notice Check if a public key is valid (on secp256k1 curve).
     */
    function _isValidPublicKey(uint256 x, uint256 y) private pure returns (bool) {
        if (x == 0 || y == 0) return false;
        uint256 PP = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
        if (x >= PP || y >= PP) return false;
        // Check y^2 = x^3 + 7 (mod p)
        uint256 lhs = mulmod(y, y, PP);
        uint256 rhs = addmod(mulmod(mulmod(x, x, PP), x, PP), 7, PP);
        return lhs == rhs;
    }

    /**
     * @notice ERC165 support — advertises VRF compatibility.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == VRF_INTERFACE_ID ||
            super.supportsInterface(interfaceId);
    }
}
