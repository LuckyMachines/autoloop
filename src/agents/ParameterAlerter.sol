// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title ParameterAlerter
/// @notice Snapshots tracked game-parameter values on every AutoLoop tick and emits an
///         immutable audit record whenever any value changes. Stealth nerfs require that
///         nobody snapshots autonomously — any human trigger can be delayed until after
///         front-running the change.
/// @dev Demonstrates: neutral autonomous snapshotting as the only tamper-proof audit trail.
contract ParameterAlerter is AutoLoopCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct ChangeRecord {
        string  key;
        uint256 oldValue;
        uint256 newValue;
        uint256 snapshotBlock;
        uint256 timestamp;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    string[] public paramKeys;
    mapping(string => uint256) public currentParams;
    mapping(string => uint256) public lastSnapshotted;
    mapping(string => bool)    public tracked;

    uint256 public checkInterval;
    uint256 public lastCheck;
    uint256 public changeCount;

    ChangeRecord[] private _auditLog;

    // ── Events ─────────────────────────────────────────────────────────────────

    event ParamAdded(string indexed key, uint256 initialValue);
    event ParamChanged(string indexed key, uint256 oldValue, uint256 newValue, uint256 timestamp);
    event SnapshotTaken(uint256 keysChecked, uint256 changesDetected, uint256 loopID);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _checkInterval Seconds between autonomous snapshot ticks
    constructor(uint256 _checkInterval) {
        require(_checkInterval > 0, "ParameterAlerter: interval=0");
        checkInterval = _checkInterval;
        lastCheck = block.timestamp;
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    /// @notice Ready when the check interval has elapsed.
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = (block.timestamp - lastCheck) >= checkInterval;
        progressWithData = abi.encode(_loopID);
    }

    /// @notice Snapshots all tracked params; records any that changed since last tick.
    function progressLoop(bytes calldata progressWithData) external override {
        uint256 loopID = abi.decode(progressWithData, (uint256));
        require((block.timestamp - lastCheck) >= checkInterval, "ParameterAlerter: too soon");
        require(loopID == _loopID, "ParameterAlerter: stale loop id");

        lastCheck = block.timestamp;
        ++_loopID;

        uint256 detected;
        for (uint256 i = 0; i < paramKeys.length; i++) {
            string memory key = paramKeys[i];
            uint256 current = currentParams[key];
            uint256 last    = lastSnapshotted[key];
            if (current != last) {
                _auditLog.push(ChangeRecord({
                    key:           key,
                    oldValue:      last,
                    newValue:      current,
                    snapshotBlock: block.number,
                    timestamp:     block.timestamp
                }));
                emit ParamChanged(key, last, current, block.timestamp);
                lastSnapshotted[key] = current;
                changeCount++;
                detected++;
            }
        }

        emit SnapshotTaken(paramKeys.length, detected, loopID);
    }

    // ── Admin — parameter management ───────────────────────────────────────────

    /// @notice Register a new tracked parameter with an initial value.
    function addTrackedParam(string calldata key, uint256 initialValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!tracked[key], "ParameterAlerter: already tracked");
        tracked[key] = true;
        paramKeys.push(key);
        currentParams[key]     = initialValue;
        lastSnapshotted[key]   = initialValue;
        emit ParamAdded(key, initialValue);
    }

    /// @notice Simulate an operator changing a game parameter.
    function setParam(string calldata key, uint256 value)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(tracked[key], "ParameterAlerter: unknown key");
        currentParams[key] = value;
    }

    /// @notice Update the check interval.
    function setCheckInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "ParameterAlerter: interval=0");
        checkInterval = _interval;
    }

    // ── Views ──────────────────────────────────────────────────────────────────

    function getAuditLogLength() external view returns (uint256) {
        return _auditLog.length;
    }

    function getAuditLog(uint256 index) external view returns (ChangeRecord memory) {
        return _auditLog[index];
    }

    function getParamKeyCount() external view returns (uint256) {
        return paramKeys.length;
    }
}
