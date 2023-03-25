// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutoLoopRoles.sol";
import "./AutoLoopCompatible.sol";

contract AutoLoopRegistry is AutoLoopRoles {
    // Mappings from registered AutoLoop or Controller Addresses
    mapping(address => bool) public isRegisteredAutoLoop;
    mapping(address => bool) public isRegisteredController;

    mapping(address => uint256) _registeredAutoLoopIndex;
    mapping(address => uint256) _registeredControllerIndex;

    // All registered AutoLoops
    address[] _registeredAutoLoops;
    address[] _registeredControllers;

    // mapping from admin to _registeredAutoLoops indices
    // this is a historical record, doesn't indicate current admin status
    mapping(address => uint256[]) _registeredAutoLoopsForAddress;

    event AutoLoopRegistered(
        address autoLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event AutoLoopDeregistered(
        address autoLoopAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event ControllerRegistered(
        address controllerAddress,
        address registrarAddress,
        uint256 timeStamp
    );

    event ControllerDeregistered(
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

    function getRegisteredAutoLoopIndicesFor(
        address adminAddress
    ) public view returns (uint256[] memory) {
        return _registeredAutoLoopsForAddress[adminAddress];
    }

    function getRegisteredAutoLoopsFor(
        address adminAddress
    ) public view returns (address[] memory autoLoops) {
        uint256 totalRegistrations = 0;
        uint256[] memory registeredLoops = _registeredAutoLoopsForAddress[
            adminAddress
        ];
        for (uint256 i = 0; i < registeredLoops.length; i++) {
            AutoLoopCompatible compatibleContract = AutoLoopCompatible(
                _registeredAutoLoops[registeredLoops[i]]
            );
            if (compatibleContract.hasRole(DEFAULT_ADMIN_ROLE, adminAddress)) {
                ++totalRegistrations;
            }
        }
        autoLoops = new address[](totalRegistrations);
        uint256 outputIndex = 0;
        for (uint256 i = 0; i < registeredLoops.length; i++) {
            AutoLoopCompatible compatibleContract = AutoLoopCompatible(
                _registeredAutoLoops[registeredLoops[i]]
            );
            if (compatibleContract.hasRole(DEFAULT_ADMIN_ROLE, adminAddress)) {
                autoLoops[outputIndex] = _registeredAutoLoops[
                    registeredLoops[i]
                ];
                ++outputIndex;
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
    // Careful here, will need to re-map any registered autoloops to new indices
    function cleanControllerList() public {}

    function cleanAutoLoopList() public {}

    // Registrar
    function registerAutoLoop(
        address registrantAddress,
        address adminAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        // Will be pre-verified by registrar to prevent duplicate registrations
        isRegisteredAutoLoop[registrantAddress] = true;
        _registeredAutoLoops.push(registrantAddress);
        _registeredAutoLoopIndex[registrantAddress] =
            _registeredAutoLoops.length -
            1;
        _registeredAutoLoopsForAddress[registrantAddress].push(
            _registeredAutoLoopIndex[registrantAddress]
        );
        _setNewAdmin(registrantAddress, adminAddress);
        emit AutoLoopRegistered(registrantAddress, msg.sender, block.timestamp);
    }

    function deregisterAutoLoop(
        address registrantAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        if (isRegisteredAutoLoop[registrantAddress]) {
            isRegisteredAutoLoop[registrantAddress] = false;
            delete _registeredAutoLoops[
                _registeredAutoLoopIndex[registrantAddress]
            ];
            delete _registeredAutoLoopIndex[registrantAddress];
            emit AutoLoopDeregistered(
                registrantAddress,
                msg.sender,
                block.timestamp
            );
        }
    }

    function registerController(
        address registrantAddress
    ) external onlyRole(REGISTRAR_ROLE) {
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

    function deregisterController(
        address registrantAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        if (isRegisteredController[registrantAddress]) {
            isRegisteredController[registrantAddress] = false;
            delete _registeredControllers[
                _registeredControllerIndex[registrantAddress]
            ];
            delete _registeredControllerIndex[registrantAddress];
            emit ControllerDeregistered(
                registrantAddress,
                msg.sender,
                block.timestamp
            );
        }
    }

    function setNewAdmin(
        address autoLoopCompatibleContract,
        address adminAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        _setNewAdmin(autoLoopCompatibleContract, adminAddress);
    }

    function _setNewAdmin(
        address autoLoopCompatibleContract,
        address adminAddress
    ) internal {
        uint256 autoLoopIndex = _registeredAutoLoopIndex[
            autoLoopCompatibleContract
        ];
        uint256[] memory existingRegistrations = _registeredAutoLoopsForAddress[
            adminAddress
        ];
        bool registrationExists;
        for (uint256 i = 0; i < existingRegistrations.length; i++) {
            if (
                _registeredAutoLoops[existingRegistrations[i]] ==
                autoLoopCompatibleContract
            ) {
                // already in registered list
                registrationExists = true;
                break;
            }
        }
        if (!registrationExists) {
            _registeredAutoLoopsForAddress[adminAddress].push(autoLoopIndex);
        }
    }
}
