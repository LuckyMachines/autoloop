// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title MockVault
/// @notice Minimal mock ERC4626-style vault used in tests and demo deployments.
contract MockVault {
    mapping(address => uint256) public shares;
    uint256 public pendingYield;
    address public harvester;

    event YieldAccrued(uint256 amount);
    event Harvested(address indexed by, uint256 amount);

    constructor(address _harvester) { harvester = _harvester; }

    function deposit() external payable { shares[msg.sender] += msg.value; }
    function accrueYield(uint256 amount) external payable { pendingYield += amount; emit YieldAccrued(amount); }

    function harvest() external returns (uint256 amount) {
        require(msg.sender == harvester, "MockVault: only harvester");
        amount = pendingYield;
        pendingYield = 0;
        if (amount > 0) {
            (bool ok,) = harvester.call{value: amount}("");
            require(ok, "MockVault: send failed");
        }
        emit Harvested(msg.sender, amount);
    }

    receive() external payable {}
}

/// @title YieldHarvester
/// @notice Compounds a vault position on a neutral schedule. Whoever triggers a harvest
///         can front-run it — watching the mempool, computing the output, sandwiching the tx.
///         AutoLoop's neutral, pre-scheduled keeper removes that attack surface.
/// @dev Demonstrates: DeFi automation where trigger timing is an attack surface.
contract YieldHarvester is AutoLoopCompatible {
    // ── State ──────────────────────────────────────────────────────────────────

    address payable public vault;
    uint256 public harvestInterval;
    uint256 public minYieldToHarvest;   // only harvest if pending yield >= this
    uint256 public lastHarvest;
    uint256 public totalHarvested;
    uint256 public harvestCount;
    uint256 public protocolFeeBalance;

    uint256 public constant PROTOCOL_FEE_BPS = 100; // 1%

    // ── Events ─────────────────────────────────────────────────────────────────

    event Harvested(uint256 indexed loopID, uint256 amount, uint256 fee, uint256 timestamp);
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _vault             Address of the vault to harvest
    /// @param _harvestInterval   Seconds between harvests
    /// @param _minYieldToHarvest Minimum pending yield required to trigger (0 = always)
    constructor(address _vault, uint256 _harvestInterval, uint256 _minYieldToHarvest) {
        require(_vault != address(0), "YieldHarvester: zero vault");
        require(_harvestInterval > 0, "YieldHarvester: interval=0");
        vault = payable(_vault);
        harvestInterval = _harvestInterval;
        minYieldToHarvest = _minYieldToHarvest;
        lastHarvest = block.timestamp;
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool intervalPassed = (block.timestamp - lastHarvest) >= harvestInterval;
        uint256 pending = MockVault(vault).pendingYield();
        loopIsReady = intervalPassed && pending >= minYieldToHarvest;
        progressWithData = abi.encode(_loopID, pending);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID,) = abi.decode(progressWithData, (uint256, uint256));
        require((block.timestamp - lastHarvest) >= harvestInterval, "YieldHarvester: too soon");
        require(loopID == _loopID, "YieldHarvester: stale loop id");

        lastHarvest = block.timestamp;
        ++_loopID;

        uint256 received = MockVault(vault).harvest();
        if (received == 0) {
            emit Harvested(loopID, 0, 0, block.timestamp);
            return;
        }

        uint256 fee = (received * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;
        totalHarvested += received - fee;
        ++harvestCount;

        emit Harvested(loopID, received - fee, fee, block.timestamp);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vault != address(0), "YieldHarvester: zero vault");
        emit VaultUpdated(vault, _vault);
        vault = payable(_vault);
    }

    function setHarvestInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "YieldHarvester: interval=0");
        harvestInterval = _interval;
    }

    function setMinYield(uint256 _min) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minYieldToHarvest = _min;
    }

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "YieldHarvester: fee withdraw failed");
    }

    receive() external payable {}
}
