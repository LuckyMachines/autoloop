// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/AutoLoopCompatible.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * @title PriceOracleTrigger
 * @notice Triggers when a Chainlink price feed crosses a threshold.
 * @dev Tracks whether price is above or below threshold to fire once per crossing.
 *
 * Example: Alert when ETH drops below $2000
 *   new PriceOracleTrigger(ETH_USD_FEED, 2000e8, false)
 */
abstract contract PriceOracleTrigger is AutoLoopCompatible {
    AggregatorV3Interface public immutable priceFeed;
    int256 public immutable threshold;
    bool public immutable triggerAbove;
    bool public lastWasAbove;
    bool public initialized;

    constructor(address _priceFeed, int256 _threshold, bool _triggerAbove) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        threshold = _threshold;
        triggerAbove = _triggerAbove;
    }

    function _isAboveThreshold() internal view returns (bool) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price >= threshold;
    }

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool currentlyAbove = _isAboveThreshold();
        if (!initialized) {
            loopIsReady = false;
        } else if (triggerAbove) {
            loopIsReady = currentlyAbove && !lastWasAbove;
        } else {
            loopIsReady = !currentlyAbove && lastWasAbove;
        }
        progressWithData = abi.encode(currentlyAbove);
    }

    function progressLoop(bytes calldata _data) external override {
        bool currentlyAbove = abi.decode(_data, (bool));
        if (!initialized) {
            initialized = true;
            lastWasAbove = currentlyAbove;
            return;
        }
        if (triggerAbove) {
            require(currentlyAbove && !lastWasAbove, "Not crossed above");
        } else {
            require(!currentlyAbove && lastWasAbove, "Not crossed below");
        }
        lastWasAbove = currentlyAbove;
        _onPriceCrossing(currentlyAbove);
    }

    function _onPriceCrossing(bool isAbove) internal virtual;
}
