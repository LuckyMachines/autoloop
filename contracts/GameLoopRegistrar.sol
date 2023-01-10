// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./GameLoopRegistry.sol";
import "./GameLoop.sol";

contract GameLoopRegistrar is GameLoopRoles {
    GameLoop GAME_LOOP;
    GameLoopRegistry REGISTRY;

    constructor(
        address gameLoopAddress,
        address registryAddress,
        address adminAddress
    ) {
        GAME_LOOP = GameLoop(gameLoopAddress);
        REGISTRY = GameLoopRegistry(registryAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    function registerGameLoop() external returns (bool success) {
        if (canRegisterGameLoop(msg.sender)) {
            REGISTRY.registerGameLoop(msg.sender);
            success = true;
        }
    }

    function unregisterGameLoop() external {
        REGISTRY.unregisterGameLoop(msg.sender);
    }

    function registerController() external returns (bool success) {
        if (canRegisterController(msg.sender)) {
            REGISTRY.registerController(msg.sender);
            GAME_LOOP.addController(msg.sender);
            success = true;
        }
    }

    function unregisterController() external {
        REGISTRY.unregisterController(msg.sender);
        GAME_LOOP.removeController(msg.sender);
    }

    function canRegisterGameLoop(address registrantAddress)
        public
        view
        returns (bool)
    {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredGameLoop(registrantAddress)) {
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
