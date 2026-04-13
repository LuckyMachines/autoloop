// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title VaultDeadSwitch
/// @notice Transfers a vault balance to a beneficiary if the owner misses a check-in window.
///         Nobody should hold this trigger — the entire point is that no human controls when it fires.
/// @dev Demonstrates: conditional transfer on inaction. Self-triggering defeats the purpose.
contract VaultDeadSwitch is AutoLoopCompatible {
    // ── State ──────────────────────────────────────────────────────────────────

    address public owner;
    address public beneficiary;
    uint256 public checkInInterval;   // seconds between required check-ins
    uint256 public lastCheckIn;       // timestamp of last owner check-in
    bool    public triggered;         // true once the switch has fired

    uint256 public protocolFeeBalance;
    uint256 public constant PROTOCOL_FEE_BPS = 200; // 2%

    // ── Events ─────────────────────────────────────────────────────────────────

    event CheckIn(address indexed owner, uint256 timestamp);
    event SwitchTriggered(address indexed beneficiary, uint256 amount, uint256 loopID);
    event Deposited(address indexed sender, uint256 amount);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _owner          Address that must check in periodically
    /// @param _beneficiary    Recipient on trigger
    /// @param _checkInInterval Seconds between required check-ins (e.g. 30 days = 2592000)
    constructor(address _owner, address _beneficiary, uint256 _checkInInterval) {
        require(_owner != address(0), "VaultDeadSwitch: zero owner");
        require(_beneficiary != address(0), "VaultDeadSwitch: zero beneficiary");
        require(_checkInInterval > 0, "VaultDeadSwitch: interval=0");
        owner = _owner;
        beneficiary = _beneficiary;
        checkInInterval = _checkInInterval;
        lastCheckIn = block.timestamp;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    /// @notice Returns true when the owner has missed their check-in window.
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = !triggered && (block.timestamp - lastCheckIn) >= checkInInterval;
        progressWithData = abi.encode(_loopID);
    }

    /// @notice Transfers vault balance to beneficiary. Takes a small protocol fee.
    function progressLoop(bytes calldata progressWithData) external override {
        uint256 loopID = abi.decode(progressWithData, (uint256));
        require(!triggered, "VaultDeadSwitch: already triggered");
        require((block.timestamp - lastCheckIn) >= checkInInterval, "VaultDeadSwitch: too soon");
        require(loopID == _loopID, "VaultDeadSwitch: stale loop id");

        triggered = true;
        ++_loopID;

        uint256 balance = address(this).balance;
        if (balance == 0) {
            emit SwitchTriggered(beneficiary, 0, loopID);
            return;
        }

        uint256 fee = (balance * PROTOCOL_FEE_BPS) / 10_000;
        uint256 payout = balance - fee;
        protocolFeeBalance += fee;

        (bool ok,) = beneficiary.call{value: payout}("");
        require(ok, "VaultDeadSwitch: transfer failed");
        emit SwitchTriggered(beneficiary, payout, loopID);
    }

    // ── Owner actions ──────────────────────────────────────────────────────────

    /// @notice Owner checks in to reset the window.
    function checkIn() external {
        require(msg.sender == owner, "VaultDeadSwitch: not owner");
        require(!triggered, "VaultDeadSwitch: already triggered");
        lastCheckIn = block.timestamp;
        emit CheckIn(msg.sender, block.timestamp);
    }

    function setBeneficiary(address _beneficiary) external {
        require(msg.sender == owner, "VaultDeadSwitch: not owner");
        require(_beneficiary != address(0), "VaultDeadSwitch: zero beneficiary");
        emit BeneficiaryUpdated(beneficiary, _beneficiary);
        beneficiary = _beneficiary;
    }

    function transferOwnership(address _newOwner) external {
        require(msg.sender == owner, "VaultDeadSwitch: not owner");
        require(_newOwner != address(0), "VaultDeadSwitch: zero owner");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    /// @notice Returns seconds remaining before the switch can fire (0 if overdue).
    function secondsUntilTrigger() external view returns (uint256) {
        uint256 elapsed = block.timestamp - lastCheckIn;
        if (elapsed >= checkInInterval) return 0;
        return checkInInterval - elapsed;
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "VaultDeadSwitch: fee withdraw failed");
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
