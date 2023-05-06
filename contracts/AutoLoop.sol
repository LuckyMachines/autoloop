// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./AutoLoopRoles.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract AutoLoop is AutoLoopRoles, ReentrancyGuard {
    event AutoLoopProgressed(
        address indexed autoLoopCompatibleContract,
        uint256 indexed timeStamp,
        address controller,
        uint256 gasUsed,
        uint256 gasPrice,
        uint256 gasCost,
        uint256 fee
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    uint256 BASE_FEE = 70; // percentage of gas cost used
    uint256 PROTOCOL_FEE_PORTION = 60; // percentage of base fee to go to protocol
    uint256 CONTROLLER_FEE_PORTION = 40; // percentage of base fee to go to controller
    uint256 MAX_GAS = 1_000_000; // default if no personal max set
    uint256 GAS_BUFFER = 122_088; // gas required to run transaction outside of contract update
    uint256 GAS_THRESHOLD = 15_000_000 - GAS_BUFFER; // highest a user could potentially set gas

    mapping(address => uint256) public balance; // balance held at this address
    mapping(address => uint256) public maxGas; // max gas a user is willing to spend on tx

    uint256 _protocolBalance;

    // PUBLIC //
    function baseFee() public view returns (uint256) {
        return BASE_FEE;
    }

    function gasBuffer() public view returns (uint256) {
        return GAS_BUFFER;
    }

    function gasThreshold() public view returns (uint256) {
        return GAS_THRESHOLD;
    }

    function maxGasDefault() public view returns (uint256) {
        return MAX_GAS;
    }

    function maxGasFor(address userAddress) public view returns (uint256) {
        if (maxGas[userAddress] == 0) {
            return MAX_GAS;
        } else {
            return maxGas[userAddress];
        }
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
        console.log("Progressing Loop %s", contractAddress);

        uint256 gasUsed = GAS_BUFFER;
        uint256 startGas = gasleft();
        // progress loop on contract
        (bool success, ) = contractAddress.call(
            abi.encodeWithSignature("progressLoop(bytes)", progressWithData)
        );
        // Calculate this first to get cost of update + this function
        gasUsed += (startGas - gasleft());

        require(success, "Unable to progress loop. Call not a success");

        uint256 gasCost = gasUsed * tx.gasprice;
        uint256 fee = (gasCost * BASE_FEE) / 100; //total fee for controller + protocol
        uint256 controllerFee = (fee * CONTROLLER_FEE_PORTION) / 100; // controller's portion of fee
        uint256 totalCost = gasCost + fee; // total cost including fee

        // update user balance based on gas used
        // Controller funds this, if this fails user account is not updated
        // and lots of gas is wasted.
        // console.log("Balance of address: %d", balance[contractAddress]);
        // console.log("Gas cost: %d", gasCost);

        require(
            balance[contractAddress] >= totalCost,
            "AutoLoop compatible contract balance too low to run update + fee."
        );
        balance[contractAddress] -= totalCost;
        (bool sent, ) = _msgSender().call{value: gasCost + controllerFee}("");
        require(sent, "Failed to repay controller");

        _protocolBalance += (fee - controllerFee);

        // console.log("Total cost: %d", totalCost);
        // console.log("Fee: %d", fee);
        // console.log("Controller fee: %d", controllerFee);
        // console.log("Protocol fee: %d", fee - controllerFee);

        emit AutoLoopProgressed(
            contractAddress,
            block.timestamp,
            _msgSender(),
            gasUsed,
            tx.gasprice,
            gasCost,
            fee
        );
    }

    // REGISTRAR //
    function addController(
        address controllerAddress
    ) public onlyRole(REGISTRAR_ROLE) {
        _grantRole(CONTROLLER_ROLE, controllerAddress);
    }

    function removeController(
        address controllerAddress
    ) public onlyRole(REGISTRAR_ROLE) {
        _revokeRole(CONTROLLER_ROLE, controllerAddress);
    }

    function deposit(
        address registeredUser
    ) external payable onlyRole(REGISTRAR_ROLE) {
        balance[registeredUser] += msg.value;
    }

    function requestRefund(
        address registeredUser,
        address toAddress
    ) external onlyRole(REGISTRAR_ROLE) nonReentrant {
        require(balance[registeredUser] > 0, "User balance is zero.");
        (bool sent, ) = toAddress.call{value: balance[registeredUser]}("");
        require(sent, "Failed to send refund");
        balance[registeredUser] = 0;
    }

    function setMaxGas(
        address registerdUser,
        uint256 maxGasAmount
    ) external onlyRole(REGISTRAR_ROLE) {
        maxGas[registerdUser] = maxGasAmount > GAS_THRESHOLD
            ? GAS_THRESHOLD
            : maxGasAmount;
    }

    // ADMIN //
    function setControllerFeePortion(
        uint256 controllerFeePercentage
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            controllerFeePercentage <= 100,
            "Percentage should be less than or equal to 100"
        );
        CONTROLLER_FEE_PORTION = controllerFeePercentage;
        PROTOCOL_FEE_PORTION = 100 - CONTROLLER_FEE_PORTION;
    }

    function setProtocolFeePortion(
        uint256 protocolFeePortion
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            protocolFeePortion <= 100,
            "Percentage should be less than or equal to 100"
        );
        PROTOCOL_FEE_PORTION = protocolFeePortion;
        CONTROLLER_FEE_PORTION = 100 - PROTOCOL_FEE_PORTION;
    }

    function setMaxGasDefault(
        uint256 maxGasDefaultValue
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        MAX_GAS = maxGasDefaultValue;
    }

    function setGasBuffer(
        uint256 gasBufferValue
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        GAS_BUFFER = gasBufferValue;
    }

    function setGasThreshold(
        uint256 gasThresholdValue
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        GAS_THRESHOLD = gasThresholdValue;
    }

    function withdrawProtocolFees(
        uint256 amount,
        address toAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(
            _protocolBalance >= amount,
            "withdraw amount greater than protocol balance"
        );
        (bool sent, ) = toAddress.call{value: _protocolBalance}("");
        require(sent, "Error withdrawing protocol fees");
        _protocolBalance -= amount;
    }

    // Internal //

    // returns usable amount of gas given a total gas amount (removes the fee)
    function _usableGas(
        uint256 totalGas
    ) internal view returns (uint256 gasAmount) {
        gasAmount = (totalGas * 100) / (100 + BASE_FEE);
    }

    function _maxGas(address user) internal view returns (uint256 gasAmount) {
        gasAmount = maxGas[user] > 0 ? maxGas[user] : MAX_GAS;

        if (gasAmount * tx.gasprice > balance[user]) {
            gasAmount = balance[user] / tx.gasprice;
        }
    }
}
