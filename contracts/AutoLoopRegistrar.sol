// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutoLoopRegistry.sol";
import "./AutoLoop.sol";

contract AutoLoopRegistrar is AutoLoopRoles {
    AutoLoop AUTO_LOOP;
    AutoLoopRegistry REGISTRY;

    constructor(
        address autoLoopAddress,
        address registryAddress,
        address adminAddress
    ) {
        AUTO_LOOP = AutoLoop(autoLoopAddress);
        REGISTRY = AutoLoopRegistry(registryAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    function registerAutoLoop() external returns (bool success) {
        if (canRegisterAutoLoop(msg.sender)) {
            REGISTRY.registerAutoLoop(msg.sender);
            success = true;
        }
    }

    function unregisterAutoLoop() external {
        REGISTRY.unregisterAutoLoop(msg.sender);
    }

    function registerController() external returns (bool success) {
        if (canRegisterController(msg.sender)) {
            REGISTRY.registerController(msg.sender);
            AUTO_LOOP.addController(msg.sender);
            success = true;
        }
    }

    function unregisterController() external {
        REGISTRY.unregisterController(msg.sender);
        AUTO_LOOP.removeController(msg.sender);
    }

    function canRegisterAutoLoop(address registrantAddress)
        public
        view
        returns (bool)
    {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredAutoLoop(registrantAddress)) {
            // already registered
            return false;
        } else {
            return true;
        }
    }

    function canRegisterController(address registrantAddress)
        public
        view
        returns (bool)
    {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredController(registrantAddress)) {
            // already registered
            return false;
        } else {
            return true;
        }
    }
}
