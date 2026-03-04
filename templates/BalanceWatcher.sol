// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/AutoLoopCompatible.sol";

/**
 * @title BalanceWatcher
 * @notice Triggers when a watched address's ETH balance drops below a threshold.
 * @dev Useful for monitoring wallets, contracts, or treasuries.
 */
abstract contract BalanceWatcher is AutoLoopCompatible {
    address public immutable watchedAddress;
    uint256 public immutable minBalance;
    bool public lastWasBelow;

    constructor(address _watchedAddress, uint256 _minBalance) {
        require(_watchedAddress != address(0), "Invalid address");
        require(_minBalance > 0, "Min balance must be > 0");
        watchedAddress = _watchedAddress;
        minBalance = _minBalance;
    }

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool isBelow = watchedAddress.balance < minBalance;
        loopIsReady = isBelow && !lastWasBelow;
        progressWithData = abi.encode(watchedAddress.balance);
    }

    function progressLoop(bytes calldata _data) external override {
        uint256 currentBalance = abi.decode(_data, (uint256));
        bool isBelow = currentBalance < minBalance;
        require(isBelow && !lastWasBelow, "Not newly below threshold");
        lastWasBelow = isBelow;
        _onBalanceLow(currentBalance);
    }

    function _onBalanceLow(uint256 currentBalance) internal virtual;
}
