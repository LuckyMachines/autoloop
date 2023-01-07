// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./GameLoopRoles.sol";

contract GameLoopRegistry is GameLoopRoles {
    mapping(address => bool) public isRegisteredGameLoop;
    mapping(address => bool) public isRegisteredController;

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

    function registerGameLoop(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        isRegisteredGameLoop[registrantAddress] = true;
        emit GameLoopRegistered(registrantAddress, msg.sender, block.timestamp);
    }

    function unregisterGameLoop(address registrantAddress)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        isRegisteredGameLoop[registrantAddress] = false;
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
        emit ControllerUnregistered(
            registrantAddress,
            msg.sender,
            block.timestamp
        );
    }
}
