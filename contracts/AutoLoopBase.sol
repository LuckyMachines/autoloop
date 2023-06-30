// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";

contract AutoLoopBase is
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRY_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    function initialize() public virtual onlyInitializing {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
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
