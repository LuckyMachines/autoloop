// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "./AutoLoopCompatibleInterface.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

abstract contract AutoLoopCompatible is
    AutoLoopCompatibleInterface,
    AccessControlEnumerable
{
    address public adminTransferRequestOrigin;
    address public adminTransferRequest;

    uint256 _loopID;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _loopID = 1;
    }

    function safeTransferAdmin(address newAdminAddress) public {
        require(
            adminTransferRequest == address(0),
            "current request in progress. can't transfer until complete or cancelled."
        );
        require(
            newAdminAddress != address(0),
            "cannot transfer admin to zero address"
        );
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Only current admin can transfer their role"
        );
        adminTransferRequestOrigin = _msgSender();
        adminTransferRequest = newAdminAddress;
    }

    function acceptTransferAdminRequest() public {
        require(
            _msgSender() == adminTransferRequest,
            "Only new admin can accept transfer request"
        );
        require(
            adminTransferRequestOrigin != address(0),
            "No pending transfer request to accept."
        );
        _revokeRole(DEFAULT_ADMIN_ROLE, adminTransferRequestOrigin);
        _grantRole(DEFAULT_ADMIN_ROLE, adminTransferRequest);
        adminTransferRequestOrigin = address(0);
        adminTransferRequest = address(0);
    }

    function cancelTransferAdminRequest() public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Only current admin can cancel transfer request"
        );
        adminTransferRequest = address(0);
        adminTransferRequestOrigin = address(0);
    }

    // ERC165 Support
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IAccessControlEnumerable).interfaceId ||
            interfaceId == type(AutoLoopCompatibleInterface).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
