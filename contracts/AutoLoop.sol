// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutoLoopRoles.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AutoLoop is AutoLoopRoles, ReentrancyGuard {
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    uint256 constant MAX_GAS = 1_000_000; // default if no personal max set
    uint256 constant GAS_BUFFER = 20_000; // potential gas required by controller, TODO: update to accurate amount
    uint256 constant GAS_THRESHOLD = 15_000_000 - GAS_BUFFER; // highest a user could potentially set gas

    mapping(address => uint256) balance; // balance held at this address
    mapping(address => uint256) maxGas; // max gas a user is willing to spend on tx

    // PUBLIC //
    function getGasBuffer() public pure returns (uint256) {
        return GAS_BUFFER;
    }

    function getGasThreshold() public pure returns (uint256) {
        return GAS_THRESHOLD;
    }

    function getMaxGas() public pure returns (uint256) {
        return MAX_GAS;
    }

    function getMaxGasFor(address userAddress) public view returns (uint256) {
        if (maxGas[userAddress] == 0) {
            return MAX_GAS;
        } else {
            return maxGas[userAddress];
        }
    }

    function getBalance(address userAddress) public view returns (uint256) {
        return balance[userAddress];
    }

    // CONTROLLER //

    // - Controller needs to send more gas than is required for tx.
    //   must have enough gas in user's account to pay for update

    /**
     * @notice progresses loop on AutoLoop compatible contract
     * @param contractAddress the address of the contract receiving update
     * @param progressWithData some data to pass along with update
     */
    function progressLoop(
        address contractAddress,
        bytes calldata progressWithData
    ) external onlyRole(CONTROLLER_ROLE) nonReentrant {
        // controller funds first check to make sure they sent enough gas
        uint256 availableGas = _maxGas(contractAddress);
        require(
            gasleft() > (availableGas + GAS_BUFFER),
            "Controller underfunded gas"
        );

        // should simulate function off-chain first to ensure it will go through
        // controller is responsible for lost gas

        uint256 startGas = gasleft();

        // progress loop on contract
        (bool success, ) = contractAddress.call(
            abi.encodeWithSignature("progressLoop(bytes)", progressWithData)
        );

        require(success, "Unable to progress loop. Call not a success");

        // get gas used from transaction
        uint256 gasUsed = startGas - gasleft();

        // update user balance based on gas used
        // Controller also funds this, if this fails user account is not updated
        // and lots of gas is wasted.
        balance[contractAddress] = balance[contractAddress] > gasUsed
            ? balance[contractAddress] - gasUsed
            : 0;
    }

    // REGISTRAR //
    function addController(address controllerAddress)
        public
        onlyRole(REGISTRAR_ROLE)
    {
        _grantRole(CONTROLLER_ROLE, controllerAddress);
    }

    function removeController(address controllerAddress)
        public
        onlyRole(REGISTRAR_ROLE)
    {
        _revokeRole(CONTROLLER_ROLE, controllerAddress);
    }

    function deposit(address registeredUser)
        external
        payable
        onlyRole(REGISTRAR_ROLE)
    {
        balance[registeredUser] += msg.value;
    }

    function requestRefund(address registeredUser)
        external
        onlyRole(REGISTRAR_ROLE)
        nonReentrant
    {
        require(balance[registeredUser] > 0, "User balance is zero.");
        (bool sent, ) = registeredUser.call{value: balance[registeredUser]}("");
        require(sent, "Failed to send refund");
    }

    function setMaxGas(address registerdUser, uint256 maxGasAmount)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        maxGas[registerdUser] = maxGasAmount > GAS_THRESHOLD
            ? GAS_THRESHOLD
            : maxGasAmount;
    }

    // Internal

    function _maxGas(address user) internal view returns (uint256 gasAmount) {
        gasAmount = maxGas[user] > 0 ? maxGas[user] : MAX_GAS;
        if (gasAmount > balance[user]) {
            gasAmount = balance[user];
        }
    }
}
