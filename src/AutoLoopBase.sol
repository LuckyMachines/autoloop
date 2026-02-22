// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract AutoLoopBase is
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public virtual onlyInitializing {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
    }

    // Admin
    function setRegistrar(
        address registrarAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(REGISTRAR_ROLE, registrarAddress);
    }

    function removeRegistrar(
        address registrarAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REGISTRAR_ROLE, registrarAddress);
    }
}
