// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title SupplyGovernanceModule
/// @notice Enforces a timelock queue for supply changes to registered item types.
///         Whenever supply changes affect asset values for all holders, no participant
///         should control execution timing — they could front-run markets before the
///         change is applied.
/// @dev Demonstrates: supply changes as a timing-as-attack-surface problem.
contract SupplyGovernanceModule is AutoLoopCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct ItemType {
        string name;
        uint256 maxSupply;
        uint256 currentSupply;
        bool frozen;
    }

    struct SupplyChange {
        uint256 itemTypeId;
        int256 delta; // positive = increase, negative = decrease
        uint256 executeAfter; // earliest execution timestamp (timelock)
        string reason;
        bool executed;
        bool cancelled;
    }

    struct ChangeRecord {
        uint256 itemTypeId;
        uint256 oldSupply;
        uint256 newSupply;
        string reason;
        uint256 timestamp;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    mapping(uint256 => ItemType) public itemTypes;
    uint256 public nextItemTypeId;

    SupplyChange[] public changeQueue;
    ChangeRecord[] private _auditLog;

    uint256 public checkInterval;
    uint256 public lastCheck;

    // ── Events ─────────────────────────────────────────────────────────────────

    event ItemTypeCreated(uint256 indexed itemTypeId, string name, uint256 maxSupply);
    event ChangeQueued(
        uint256 indexed changeIndex,
        uint256 indexed itemTypeId,
        int256 delta,
        uint256 executeAfter,
        string reason
    );
    event SupplyChanged(
        uint256 indexed itemTypeId, uint256 oldSupply, uint256 newSupply, string reason
    );
    event ChangeCancelled(uint256 indexed changeIndex);
    event ItemFrozen(uint256 indexed itemTypeId);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _checkInterval Seconds between keeper readiness checks
    constructor(uint256 _checkInterval) {
        require(_checkInterval > 0, "SupplyGovernance: interval=0");
        checkInterval = _checkInterval;
        lastCheck = block.timestamp;
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    /// @notice Ready when interval has passed and at least one change is executable.
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool intervalPassed = (block.timestamp - lastCheck) >= checkInterval;
        uint256 readyIdx = _firstExecutableChange();
        loopIsReady = intervalPassed && readyIdx != type(uint256).max;
        progressWithData = abi.encode(_loopID, readyIdx);
    }

    /// @notice Execute the first change whose timelock has expired.
    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID, uint256 changeIdx) = abi.decode(progressWithData, (uint256, uint256));
        require((block.timestamp - lastCheck) >= checkInterval, "SupplyGovernance: too soon");
        require(loopID == _loopID, "SupplyGovernance: stale loop id");

        lastCheck = block.timestamp;
        ++_loopID;

        SupplyChange storage sc = changeQueue[changeIdx];
        require(!sc.executed, "SupplyGovernance: already executed");
        require(!sc.cancelled, "SupplyGovernance: cancelled");
        require(block.timestamp >= sc.executeAfter, "SupplyGovernance: timelock active");

        ItemType storage item = itemTypes[sc.itemTypeId];
        require(!item.frozen, "SupplyGovernance: item frozen");

        uint256 oldSupply = item.currentSupply;
        uint256 newSupply;

        if (sc.delta >= 0) {
            uint256 increase = uint256(sc.delta);
            newSupply = oldSupply + increase;
            if (newSupply > item.maxSupply) newSupply = item.maxSupply;
        } else {
            uint256 decrease = uint256(-sc.delta);
            newSupply = oldSupply > decrease ? oldSupply - decrease : 0;
        }

        item.currentSupply = newSupply;
        sc.executed = true;

        _auditLog.push(
            ChangeRecord({
                itemTypeId: sc.itemTypeId,
                oldSupply: oldSupply,
                newSupply: newSupply,
                reason: sc.reason,
                timestamp: block.timestamp
            })
        );

        emit SupplyChanged(sc.itemTypeId, oldSupply, newSupply, sc.reason);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    /// @notice Register a new item type.
    function createItemType(string calldata name, uint256 maxSupply)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 itemTypeId)
    {
        require(maxSupply > 0, "SupplyGovernance: zero maxSupply");
        itemTypeId = nextItemTypeId++;
        itemTypes[itemTypeId] =
            ItemType({name: name, maxSupply: maxSupply, currentSupply: 0, frozen: false});
        emit ItemTypeCreated(itemTypeId, name, maxSupply);
    }

    /// @notice Queue a supply change with a mandatory timelock delay.
    /// @param delay Minimum seconds that must pass before execution (timelock).
    function queueSupplyChange(
        uint256 itemTypeId,
        int256 delta,
        string calldata reason,
        uint256 delay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 changeIdx) {
        require(itemTypeId < nextItemTypeId, "SupplyGovernance: unknown item");
        require(!itemTypes[itemTypeId].frozen, "SupplyGovernance: item frozen");
        require(delta != 0, "SupplyGovernance: zero delta");

        changeIdx = changeQueue.length;
        changeQueue.push(
            SupplyChange({
                itemTypeId: itemTypeId,
                delta: delta,
                executeAfter: block.timestamp + delay,
                reason: reason,
                executed: false,
                cancelled: false
            })
        );
        emit ChangeQueued(changeIdx, itemTypeId, delta, block.timestamp + delay, reason);
    }

    /// @notice Cancel a pending change.
    function cancelChange(uint256 changeIdx) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!changeQueue[changeIdx].executed, "SupplyGovernance: already executed");
        require(!changeQueue[changeIdx].cancelled, "SupplyGovernance: already cancelled");
        changeQueue[changeIdx].cancelled = true;
        emit ChangeCancelled(changeIdx);
    }

    /// @notice Freeze an item type — no further supply changes allowed.
    function freezeItem(uint256 itemTypeId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(itemTypeId < nextItemTypeId, "SupplyGovernance: unknown item");
        itemTypes[itemTypeId].frozen = true;
        emit ItemFrozen(itemTypeId);
    }

    /// @notice Update the check interval.
    function setCheckInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "SupplyGovernance: interval=0");
        checkInterval = _interval;
    }

    // ── Views ──────────────────────────────────────────────────────────────────

    function getAuditLogLength() external view returns (uint256) {
        return _auditLog.length;
    }

    function getAuditLog(uint256 index) external view returns (ChangeRecord memory) {
        return _auditLog[index];
    }

    function getChangeQueueLength() external view returns (uint256) {
        return changeQueue.length;
    }

    function pendingChangeCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < changeQueue.length; i++) {
            if (!changeQueue[i].executed && !changeQueue[i].cancelled) count++;
        }
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    function _firstExecutableChange() internal view returns (uint256) {
        for (uint256 i = 0; i < changeQueue.length; i++) {
            SupplyChange storage sc = changeQueue[i];
            if (!sc.executed && !sc.cancelled && block.timestamp >= sc.executeAfter) {
                return i;
            }
        }
        return type(uint256).max;
    }
}
