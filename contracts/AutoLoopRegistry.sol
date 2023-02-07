// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutoLoopRoles.sol";

contract AutoLoopRegistry is AutoLoopRoles {
    mapping(address => bool) public isRegisteredAutoLoop;
    mapping(address => bool) public isRegisteredController;

    mapping(address => uint256) _registeredAutoLoopIndex;
    mapping(address => uint256) _registeredControllerIndex;
    address[] _registeredAutoLoops;
    address[] _registeredControllers;

    event AutoLoopRegistered(
        address autoLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event AutoLoopUnregistered(
        address autoLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event ControllerRegistered(
        address controllerAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event ControllerUnregistered(
        address controllerAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    constructor(address adminAddress) {
        _setupRole(DEFAULT_ADMIN_ROLE, adminAddress);
    }

    // Public
    function getRegisteredAutoLoops()
        public
        view
        returns (address[] memory autoLoops)
    {
        uint256 nonZeroAddresses = 0;
        for (uint256 i = 0; i < _registeredAutoLoops.length; i++) {
            if (_registeredAutoLoops[i] != address(0)) {
                ++nonZeroAddresses;
            }
        }
        autoLoops = new address[](nonZeroAddresses);
        uint256 offset = 0;
        for (uint256 i = 0; i < _registeredAutoLoops.length; i++) {
            if (_registeredAutoLoops[i] != address(0)) {
                autoLoops[offset] = _registeredAutoLoops[i];
                ++offset;
            }
        }
    }

    function getRegisteredControllers()
        public
        view
        returns (address[] memory controllers)
    {
        uint256 nonZeroAddresses = 0;
        for (uint256 i = 0; i < _registeredControllers.length; i++) {
            if (_registeredControllers[i] != address(0)) {
                ++nonZeroAddresses;
            }
        }
        controllers = new address[](nonZeroAddresses);
        uint256 offset = 0;
        for (uint256 i = 0; i < _registeredControllers.length; i++) {
            if (_registeredControllers[i] != address(0)) {
                controllers[offset] = _registeredControllers[i];
                ++offset;
            }
        }
    }

    // Cleanup
    // TODO: remove zero addresses from registration lists
    function cleanControllerList() public {}

    function cleanAutoLoopList() public {}

    // Registrar
    function registerAutoLoop(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        // Will be pre-verified by registrar to prevent duplicate registrations
        isRegisteredAutoLoop[registrantAddress] = true;
        _registeredAutoLoops.push(registrantAddress);
        _registeredAutoLoopIndex[registrantAddress] =
            _registeredAutoLoops.length -
            1;
        emit AutoLoopRegistered(registrantAddress, msg.sender, block.timestamp);
    }

    function unregisterAutoLoop(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        if (isRegisteredAutoLoop[registrantAddress]) {
            isRegisteredAutoLoop[registrantAddress] = false;
            delete _registeredAutoLoops[
                _registeredAutoLoopIndex[registrantAddress]
            ];
            delete _registeredAutoLoopIndex[registrantAddress];
            emit AutoLoopUnregistered(
                registrantAddress,
                msg.sender,
                block.timestamp
            );
        }
    }

    function registerController(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        isRegisteredController[registrantAddress] = true;
        _registeredControllers.push(registrantAddress);
        _registeredControllerIndex[registrantAddress] =
            _registeredControllers.length -
            1;
        emit ControllerRegistered(
            registrantAddress,
            msg.sender,
            block.timestamp
        );
    }

    function unregisterController(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        if (isRegisteredController[registrantAddress]) {
            isRegisteredController[registrantAddress] = false;
            delete _registeredControllers[
                _registeredControllerIndex[registrantAddress]
            ];
            delete _registeredControllerIndex[registrantAddress];
            emit ControllerUnregistered(
                registrantAddress,
                msg.sender,
                block.timestamp
            );
        }
    }
}
