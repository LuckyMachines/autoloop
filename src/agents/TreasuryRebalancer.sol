// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title TreasuryRebalancer
/// @notice Monitors a two-token treasury against target weights and emits a
///         RebalanceRequired signal when drift exceeds a threshold. Off-chain executors
///         act on the signal. Nobody should hold the trigger — whoever triggers knows
///         the exact swap in advance and can front-run it.
/// @dev Demonstrates: DeFi treasury management as a front-running attack surface.
///      The contract detects drift; it does not execute swaps (that's the off-chain layer).
contract TreasuryRebalancer is AutoLoopCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct TokenConfig {
        address token;       // ERC20 address (address(0) = native ETH)
        uint256 targetBps;   // target weight in basis points (sum must = 10000)
        string  symbol;
    }

    struct RebalanceRecord {
        uint256 loopID;
        uint256 timestamp;
        uint256 token0BalanceBps;
        uint256 token1BalanceBps;
        uint256 driftBps;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    TokenConfig public token0;
    TokenConfig public token1;

    uint256 public driftThresholdBps;   // trigger rebalance when drift > this (e.g. 500 = 5%)
    uint256 public checkInterval;
    uint256 public lastCheck;
    uint256 public rebalanceCount;

    /// Price oracle: returns token0 value in token1 units (18 decimals).
    /// Set to address(0) to use a 1:1 mock ratio (for demos).
    address public priceOracle;

    RebalanceRecord[] public history;

    // ── Events ─────────────────────────────────────────────────────────────────

    /// @notice Off-chain executors listen for this and submit the actual swap.
    event RebalanceRequired(
        uint256 indexed loopID,
        address tokenIn,
        address tokenOut,
        uint256 currentBps,
        uint256 targetBps,
        uint256 driftBps
    );
    event DriftWithinBounds(uint256 indexed loopID, uint256 driftBps);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _token0        Address of token0 (address(0) = ETH)
    /// @param _token0Target  Target weight for token0 in bps (e.g. 6000 = 60%)
    /// @param _token1        Address of token1
    /// @param _driftThreshold Rebalance when |actual - target| > this (bps)
    /// @param _checkInterval Seconds between drift checks
    constructor(
        address _token0,
        uint256 _token0Target,
        address _token1,
        uint256 _driftThreshold,
        uint256 _checkInterval
    ) {
        require(_token0Target <= 10_000, "TreasuryRebalancer: target0 > 100%");
        require(_driftThreshold > 0, "TreasuryRebalancer: drift=0");
        require(_checkInterval > 0, "TreasuryRebalancer: interval=0");

        token0 = TokenConfig({ token: _token0, targetBps: _token0Target, symbol: "T0" });
        token1 = TokenConfig({ token: _token1, targetBps: 10_000 - _token0Target, symbol: "T1" });
        driftThresholdBps = _driftThreshold;
        checkInterval = _checkInterval;
        lastCheck = block.timestamp;
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool intervalPassed = (block.timestamp - lastCheck) >= checkInterval;
        if (!intervalPassed) return (false, abi.encode(_loopID));
        (uint256 t0Bps, uint256 drift) = _currentDrift();
        loopIsReady = drift > driftThresholdBps;
        progressWithData = abi.encode(_loopID, t0Bps, drift);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID, uint256 t0Bps, uint256 drift) =
            abi.decode(progressWithData, (uint256, uint256, uint256));
        require((block.timestamp - lastCheck) >= checkInterval, "TreasuryRebalancer: too soon");
        require(loopID == _loopID, "TreasuryRebalancer: stale loop id");

        lastCheck = block.timestamp;
        ++_loopID;
        ++rebalanceCount;

        uint256 t1Bps = 10_000 - t0Bps;
        history.push(RebalanceRecord({
            loopID: loopID,
            timestamp: block.timestamp,
            token0BalanceBps: t0Bps,
            token1BalanceBps: t1Bps,
            driftBps: drift
        }));

        if (drift > driftThresholdBps) {
            // Determine direction: if token0 overweight, sell token0 for token1
            address tokenIn  = t0Bps > token0.targetBps ? token0.token : token1.token;
            address tokenOut = t0Bps > token0.targetBps ? token1.token : token0.token;
            uint256 tgtBps   = t0Bps > token0.targetBps ? token0.targetBps : token1.targetBps;
            emit RebalanceRequired(loopID, tokenIn, tokenOut, t0Bps > token0.targetBps ? t0Bps : t1Bps, tgtBps, drift);
        } else {
            emit DriftWithinBounds(loopID, drift);
        }
    }

    // ── Drift calculation ─────────────────────────────────────────────────────

    /// @notice Returns token0 weight in bps and absolute drift from target.
    function _currentDrift() internal view returns (uint256 t0Bps, uint256 drift) {
        uint256 v0 = _valueOf(token0.token);
        uint256 v1 = _valueOf(token1.token);
        uint256 total = v0 + v1;
        if (total == 0) return (token0.targetBps, 0);
        t0Bps = (v0 * 10_000) / total;
        drift = t0Bps > token0.targetBps
            ? t0Bps - token0.targetBps
            : token0.targetBps - t0Bps;
    }

    /// @notice Returns the ETH-denominated value of a token holding.
    ///         Uses priceOracle if set; falls back to raw balance (1:1 mock).
    function _valueOf(address token) internal view returns (uint256) {
        if (token == address(0)) return address(this).balance;
        // For mock/demo: treat ERC20 balance as ETH-equivalent (1:1)
        // Real deployment sets priceOracle to a TWAP or Chainlink feed
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        if (!ok || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    function currentDrift() external view returns (uint256 t0Bps, uint256 drift) {
        return _currentDrift();
    }

    function historyLength() external view returns (uint256) { return history.length; }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setDriftThreshold(uint256 _bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bps > 0, "TreasuryRebalancer: drift=0");
        driftThresholdBps = _bps;
    }

    function setCheckInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "TreasuryRebalancer: interval=0");
        checkInterval = _interval;
    }

    function setPriceOracle(address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceOracle = _oracle;
    }

    receive() external payable {}
}
