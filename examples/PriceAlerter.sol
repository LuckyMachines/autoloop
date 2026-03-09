// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../src/AutoLoopCompatible.sol";
import "../src/AutoLoopRegistrar.sol";

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );
}

/// @title PriceAlerter
/// @notice Emits alerts when ETH/USD price crosses a threshold.
/// @dev Uses Chainlink price feeds. Fires once per crossing direction.
contract PriceAlerter is AutoLoopCompatible {
    event PriceAlert(
        uint256 indexed alertNumber,
        int256 price,
        int256 threshold,
        bool crossedAbove,
        uint256 timestamp
    );

    AggregatorV3Interface public immutable priceFeed;
    int256 public threshold;
    bool public lastAbove;
    bool public initialized;
    uint256 public alertCount;
    int256 public lastPrice;

    /// @param _priceFeed Chainlink price feed address (e.g. ETH/USD)
    /// @param _threshold Price threshold in feed decimals (e.g. 2000e8 for $2000)
    constructor(address _priceFeed, int256 _threshold) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        threshold = _threshold;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    function setThreshold(int256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        threshold = _threshold;
        initialized = false; // Reset to re-initialize with new threshold
    }

    function _currentPrice() internal view returns (int256) {
        (, int256 answer, , ,) = priceFeed.latestRoundData();
        return answer;
    }

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        int256 price = _currentPrice();
        bool currentlyAbove = price >= threshold;

        if (!initialized) {
            loopIsReady = true; // Initialize on first run
        } else {
            loopIsReady = currentlyAbove != lastAbove; // Crossed threshold
        }
        progressWithData = abi.encode(_loopID, price);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID, int256 price) = abi.decode(progressWithData, (uint256, int256));
        require(loopID == _loopID, "Stale loop ID");

        bool currentlyAbove = price >= threshold;

        if (!initialized) {
            initialized = true;
            lastAbove = currentlyAbove;
            lastPrice = price;
            ++_loopID;
            return;
        }

        require(currentlyAbove != lastAbove, "No crossing");

        alertCount++;
        lastPrice = price;
        lastAbove = currentlyAbove;

        emit PriceAlert(alertCount, price, threshold, currentlyAbove, block.timestamp);
        ++_loopID;
    }
}
