// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutoLoopRegistry.sol";
import "./AutoLoop.sol";
import "./AutoLoopCompatible.sol";

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

    // self-register contract
    function registerAutoLoop() external returns (bool success) {
        // pass msg.sender as both arguments since it is both registrant and contract being registered
        if (canRegisterAutoLoop(msg.sender, msg.sender)) {
            _registerAutoLoop(msg.sender);
            success = true;
        }
    }

    // self-unregister contract
    function unregisterAutoLoop() external returns (bool success) {
        if (canRegisterAutoLoop(msg.sender, msg.sender)) {
            _unregisterAutoLoop(msg.sender);
            success = true;
        }
    }

    // admin register contract
    function registerAutoLoopFor(address autoLoopCompatibleContract)
        external
        returns (bool success)
    {
        if (canRegisterAutoLoop(msg.sender, autoLoopCompatibleContract)) {
            _registerAutoLoop(autoLoopCompatibleContract);
            success = true;
        }
    }

    // admin unregister contract
    function unregisterAutoLoopFor(address autoLoopCompatibleContract)
        external
        returns (bool success)
    {
        if (canRegisterAutoLoop(msg.sender, autoLoopCompatibleContract)) {
            _unregisterAutoLoop(autoLoopCompatibleContract);
            success = true;
        }
    }

    // controllers register themselves
    function registerController() external returns (bool success) {
        if (canRegisterController(msg.sender)) {
            _registerController(msg.sender);
            success = true;
        }
    }

    function unregisterController() external {
        _unregisterController(msg.sender);
    }

    function canRegisterAutoLoop(
        address registrantAddress,
        address autoLoopCompatibleContract
    ) public view returns (bool) {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredAutoLoop(registrantAddress)) {
            // already registered
            return false;
        } else if (registrantAddress != autoLoopCompatibleContract) {
            // check if registrant is admin on contract
            return
                AutoLoopCompatible(autoLoopCompatibleContract).hasRole(
                    DEFAULT_ADMIN_ROLE,
                    registrantAddress
                );
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

    // internal
    function _registerAutoLoop(address registrant) internal {
        REGISTRY.registerAutoLoop(registrant);
    }

    function _unregisterAutoLoop(address registrant) internal {
        REGISTRY.unregisterAutoLoop(registrant);
    }

    function _registerController(address registrant) internal {
        REGISTRY.registerController(registrant);
        AUTO_LOOP.addController(registrant);
    }

    function _unregisterController(address registrant) internal {
        REGISTRY.unregisterController(registrant);
        AUTO_LOOP.removeController(registrant);
    }
}
