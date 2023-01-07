// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./GameLoopRegistry.sol";

contract GameLoopRegistrar is GameLoopRoles {
    GameLoopRegistry REGISTRY;

    constructor(address registryAddress, address adminAddress) {
        REGISTRY = GameLoopRegistry(registryAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    function registerGameLoop() external returns (bool success) {
        if (_canRegisterGameLoop(msg.sender)) {
            REGISTRY.registerGameLoop(msg.sender);
            success = true;
        }
    }

    function registerController() external returns (bool success) {
        if (_canRegisterController(msg.sender)) {
            REGISTRY.registerController(msg.sender);
            success = true;
        }
    }

    function _canRegisterGameLoop(address registrantAddress)
        internal
        view
        returns (bool canRegister)
    {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            canRegister == false;
        } else if (REGISTRY.isRegisteredGameLoop(registrantAddress)) {
            // already registered
            canRegister = false;
        } else {
            canRegister == true;
        }
    }

    function _canRegisterController(address registrantAddress)
        internal
        view
        returns (bool canRegister)
    {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            canRegister == false;
        } else if (REGISTRY.isRegisteredController(registrantAddress)) {
            // already registered
            canRegister = false;
        } else {
            canRegister == true;
        }
    }
}
