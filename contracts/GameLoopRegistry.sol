// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./GameLoopRoles.sol";

contract GameLoopRegistry is GameLoopRoles {
    mapping(address => bool) public isRegisteredGameLoop;
    mapping(address => bool) public isRegisteredController;

    mapping(address => uint256) _registeredGameLoopIndex;
    mapping(address => uint256) _registeredControllerIndex;
    address[] _registeredGameLoops;
    address[] _registeredControllers;

    event GameLoopRegistered(
        address gameLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event GameLoopUnregistered(
        address gameLoopAddress,
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
    function getRegisteredGameLoops()
        public
        view
        returns (address[] memory gameLoops)
    {
        uint256 nonZeroAddresses = 0;
        for (uint256 i = 0; i < _registeredGameLoops.length; i++) {
            if (_registeredGameLoops[i] != address(0)) {
                ++nonZeroAddresses;
            }
        }
        gameLoops = new address[](nonZeroAddresses);
        uint256 offset = 0;
        for (uint256 i = 0; i < _registeredGameLoops.length; i++) {
            if (_registeredGameLoops[i] != address(0)) {
                gameLoops[offset] = _registeredGameLoops[i];
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

    function cleanGameLoopList() public {}

    // Registrar
    function registerGameLoop(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        // Will be pre-verified by registrar to prevent duplicate registrations
        isRegisteredGameLoop[registrantAddress] = true;
        _registeredGameLoops.push(registrantAddress);
        _registeredGameLoopIndex[registrantAddress] =
            _registeredGameLoops.length -
            1;
        emit GameLoopRegistered(registrantAddress, msg.sender, block.timestamp);
    }

    function unregisterGameLoop(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        isRegisteredGameLoop[registrantAddress] = false;
        delete _registeredGameLoops[
            _registeredGameLoopIndex[registrantAddress]
        ];
        delete _registeredGameLoopIndex[registrantAddress];
        emit GameLoopUnregistered(
            registrantAddress,
            msg.sender,
            block.timestamp
        );
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
