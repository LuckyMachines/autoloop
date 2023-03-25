// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AutoLoopCompatibleInterface.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

abstract contract AutoLoopCompatible is
    AutoLoopCompatibleInterface,
    AccessControlEnumerable
{
    address _adminTransferRequest;

    function safeTransferAdmin(address newAdminAddress) public {
        require(
            newAdminAddress != address(0),
            "cannot transfer admin to zero address"
        );
        _adminTransferRequest = newAdminAddress;
    }

    function acceptTransferAdminRequest() public {
        require(
            _msgSender() == _adminTransferRequest,
            "Only new admin can accept transfer request"
        );
        _setupRole(DEFAULT_ADMIN_ROLE, _adminTransferRequest);
        _adminTransferRequest = address(0);
    }

    function cancelTransferAdminRequest() public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Only current admin can cancel transfer request"
        );
        _adminTransferRequest = address(0);
    }
}
