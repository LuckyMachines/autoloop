// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

abstract contract GameLoopRoles is AccessControlEnumerable {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRY_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    // Admin
    function setRegistrar(address registrarAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        grantRole(REGISTRAR_ROLE, registrarAddress);
    }

    function removeRegistrar(address registrarAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revokeRole(REGISTRAR_ROLE, registrarAddress);
    }
}
