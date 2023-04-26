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

    // IN PROGRESS
    // Draft functions:
    function deposit(address registeredContract) external payable {
        require(msg.value > 0, "no value deposited");
        require(
            REGISTRY.isRegisteredAutoLoop(registeredContract),
            "cannot deposit to unregistered contract"
        );
        AUTO_LOOP.deposit{value: msg.value}(registeredContract);
    }

    function requestRefund(address toAddress) external {
        // controller or contract
        AUTO_LOOP.requestRefund(msg.sender, toAddress);
    }

    function requestRefundFor(
        address registeredContract,
        address toAddress
    ) external {
        require(
            _isAdmin(msg.sender, registeredContract),
            "Cannot request refund. Caller is not admin on contract."
        );
        AUTO_LOOP.requestRefund(registeredContract, toAddress);
    }

    function registerSafeTransfer(
        address autoLoopCompatibleContract,
        address newAdminAddress
    ) external {
        require(
            _isAdmin(msg.sender, autoLoopCompatibleContract),
            "Cannot set gas, caller is not admin on contract"
        );
        REGISTRY.setNewAdmin(autoLoopCompatibleContract, newAdminAddress);
    }

    function setMaxGas(uint256 maxGasPerUpdate) external {
        require(
            REGISTRY.isRegisteredAutoLoop(msg.sender),
            "cannot set max gas on unregistered contract"
        );
        AUTO_LOOP.setMaxGas(msg.sender, maxGasPerUpdate);
    }

    function setMaxGasFor(
        address registeredContract,
        uint256 maxGasPerUpdate
    ) external {
        require(
            _isAdmin(msg.sender, registeredContract),
            "Cannot set gas, caller is not admin on contract"
        );
        require(
            REGISTRY.isRegisteredAutoLoop(registeredContract),
            "cannot set max gas on unregistered contract"
        );
        AUTO_LOOP.setMaxGas(registeredContract, maxGasPerUpdate);
    }

    /**
     * @notice check if a contract can be registered
     * @param registrantAddress the address that will register the contract (address of the contract if self-registering)
     * @param autoLoopCompatibleContract the AutoLoop compatible contract to be registered
     * @return canRegister - whether or not the contract can be registered
     */
    function canRegisterAutoLoop(
        address registrantAddress,
        address autoLoopCompatibleContract
    ) public view returns (bool canRegister) {
        // some logic to determine if address can register
        if (registrantAddress == address(0)) {
            // zero address can't register
            return false;
        } else if (REGISTRY.isRegisteredAutoLoop(autoLoopCompatibleContract)) {
            // already registered
            return false;
        } else if (registrantAddress != autoLoopCompatibleContract) {
            // check if registrant is admin on contract
            return _isAdmin(registrantAddress, autoLoopCompatibleContract);
        } else {
            return true;
        }
    }

    /**
     * @notice check if a controller can be registered
     * @param registrantAddress the address of the controller to be registered
     * @return canRegister - whether or not the controller can be registered
     */
    function canRegisterController(
        address registrantAddress
    ) public view returns (bool canRegister) {
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

    /**
     * @notice AutoLoop compatible contract registers itself. ACCs can have multiple admins, admin at 0 is indexed.
     * @return success - whether the registration was successful or not
     */
    function registerAutoLoop() external returns (bool success) {
        // pass msg.sender as both arguments since it is both registrant and contract being registered
        if (canRegisterAutoLoop(msg.sender, msg.sender)) {
            address adminAddress = AutoLoopCompatible(msg.sender).getRoleMember(
                DEFAULT_ADMIN_ROLE,
                0
            );
            _registerAutoLoop(msg.sender, adminAddress);
            success = true;
        }
    }

    /**
     * @notice register an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being registered). This will associate this particular admin with this contract instead of the default admin at the first index.
     * @param autoLoopCompatibleContract the address of the contract to register
     * @return success - whether or not the contract was registered
     */
    function registerAutoLoopFor(
        address autoLoopCompatibleContract,
        uint256 maxGasPerUpdate
    ) external payable returns (bool success) {
        if (canRegisterAutoLoop(msg.sender, autoLoopCompatibleContract)) {
            _registerAutoLoop(autoLoopCompatibleContract, msg.sender);
            if (msg.value > 0) {
                AUTO_LOOP.deposit{value: msg.value}(autoLoopCompatibleContract);
            }
            if (maxGasPerUpdate > 0) {
                AUTO_LOOP.setMaxGas(
                    autoLoopCompatibleContract,
                    maxGasPerUpdate
                );
            }
            success = true;
        }
    }

    /**
     * @notice register an AutoLoop controller
     * @return success - whether or not the controller was registered
     */
    function registerController() external returns (bool success) {
        if (canRegisterController(msg.sender)) {
            _registerController(msg.sender);
            success = true;
        }
    }

    /**
     * @notice Claim an AutoLoop contract for UI access. Useful for contracts with multiple admins.
     */
    function claimAutoLoop(address autoLoopCompatibleContract) external {
        require(
            _isAdmin(msg.sender, autoLoopCompatibleContract),
            "Cannot claim contract. Sender is not admin"
        );
        REGISTRY.setNewAdmin(autoLoopCompatibleContract, msg.sender);
    }

    /**
     * @notice AutoLoop compatible contract deregisters itself
     * @return success - whether the unregistration was successful or not
     */
    function deregisterAutoLoop() external returns (bool success) {
        _deregisterAutoLoop(msg.sender);
        success = true;
    }

    /**
     * @notice deregister an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being deregistered)
     * @param autoLoopCompatibleContract the address of the contract to deregister
     * @return success - whether or not the contract was deregistered
     */
    function deregisterAutoLoopFor(
        address autoLoopCompatibleContract
    ) external returns (bool success) {
        if (_isAdmin(msg.sender, autoLoopCompatibleContract)) {
            _deregisterAutoLoop(autoLoopCompatibleContract);
            success = true;
        }
    }

    /**
     * @notice uregister an AutoLoop controller
     */
    function deregisterController() external {
        _deregisterController(msg.sender);
    }

    // internal
    function _isAdmin(
        address testAddress,
        address contractAddress
    ) internal view returns (bool) {
        return
            AutoLoopCompatible(contractAddress).hasRole(
                DEFAULT_ADMIN_ROLE,
                testAddress
            );
    }

    /**
     * @dev registers AutoLoop compatible contract. This should not be called unless a pre-check has been made to verify the contract can be registered.
     */
    function _registerAutoLoop(
        address registrant,
        address adminAddress
    ) internal {
        REGISTRY.registerAutoLoop(registrant, adminAddress);
    }

    /**
     * @dev deregisters AutoLoop compatible contract if possible. No pre-checks are required although they can save gas on a redundant call to deregister.
     */
    function _deregisterAutoLoop(address registrant) internal {
        REGISTRY.deregisterAutoLoop(registrant);
    }

    /**
     * @dev registers controller. This should not be called unless a pre-check has been made to verify the controller can be registered.
     */
    function _registerController(address registrant) internal {
        REGISTRY.registerController(registrant);
        AUTO_LOOP.addController(registrant);
    }

    /**
     * @dev deregisters controller if possible. No pre-checks are required although they can save gas on a redundant call to deregister.
     */
    function _deregisterController(address registrant) internal {
        REGISTRY.deregisterController(registrant);
        AUTO_LOOP.removeController(registrant);
    }
}