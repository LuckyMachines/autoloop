// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./GameLoopRoles.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GameLoop is GameLoopRoles, ReentrancyGuard {
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    uint256 public constant MAX_GAS = 1_000_000; // default if no personal max set
    uint256 public constant GAS_BUFFER = 20_000; // potential gas required by controller
    uint256 constant GAS_THRESHOLD = 15_000_000 - GAS_BUFFER; // highest a user could potentially set gas

    mapping(address => uint256) public balance; // balance held at this address
    mapping(address => uint256) public maxGas; // max gas a user is willing to spend on tx

    // CONTROLLER //

    // - Controller needs to send more gas than is required for tx.
    //   must have enough gas in user's account to pay for update

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
        (bool sent, bytes memory data) = registeredUser.call{
            value: balance[registeredUser]
        }("");
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
