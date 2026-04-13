// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title DAOExecutor
/// @notice Executes queued governance proposals after their timelock expires, on an
///         autonomous schedule. No member needs to manually execute — and no member should
///         control when they do. Whoever controls execution timing can front-run the
///         proposal's on-chain effects.
/// @dev Demonstrates: governance execution as a timing-as-attack-surface problem.
contract DAOExecutor is AutoLoopCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct Proposal {
        uint256 id;
        address target;
        bytes   callData;
        uint256 eta;          // earliest execution timestamp
        bool    executed;
        bool    cancelled;
        string  description;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    uint256 public nextProposalId;
    uint256 public checkInterval;   // how often AutoLoop checks for ready proposals
    uint256 public lastCheck;
    uint256 public executedCount;
    uint256 public protocolFeeBalance;

    mapping(uint256 => Proposal) public proposals;
    uint256[] public proposalQueue;  // ids of pending proposals

    // ── Events ─────────────────────────────────────────────────────────────────

    event ProposalQueued(uint256 indexed id, address target, uint256 eta, string description);
    event ProposalExecuted(uint256 indexed id, address target, bool success, uint256 loopID);
    event ProposalCancelled(uint256 indexed id);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _checkInterval Seconds between AutoLoop readiness checks
    constructor(uint256 _checkInterval) {
        require(_checkInterval > 0, "DAOExecutor: interval=0");
        checkInterval = _checkInterval;
        lastCheck = block.timestamp;
    }

    // ── Governance actions ─────────────────────────────────────────────────────

    /// @notice Queue a proposal. Only admin (governance contract or multisig).
    function queueProposal(
        address target,
        bytes calldata callData,
        uint256 eta,
        string calldata description
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 id) {
        require(target != address(0), "DAOExecutor: zero target");
        require(eta > block.timestamp, "DAOExecutor: eta in past");
        id = nextProposalId++;
        proposals[id] = Proposal({
            id: id,
            target: target,
            callData: callData,
            eta: eta,
            executed: false,
            cancelled: false,
            description: description
        });
        proposalQueue.push(id);
        emit ProposalQueued(id, target, eta, description);
    }

    function cancelProposal(uint256 id) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!proposals[id].executed, "DAOExecutor: already executed");
        proposals[id].cancelled = true;
        emit ProposalCancelled(id);
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    /// @notice Ready when at least one queued proposal has passed its eta.
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool intervalPassed = (block.timestamp - lastCheck) >= checkInterval;
        uint256 readyId = _firstReadyProposal();
        loopIsReady = intervalPassed && readyId != type(uint256).max;
        progressWithData = abi.encode(_loopID, readyId);
    }

    /// @notice Execute the first ready proposal.
    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID, uint256 proposalId) = abi.decode(progressWithData, (uint256, uint256));
        require((block.timestamp - lastCheck) >= checkInterval, "DAOExecutor: too soon");
        require(loopID == _loopID, "DAOExecutor: stale loop id");

        lastCheck = block.timestamp;
        ++_loopID;

        Proposal storage p = proposals[proposalId];
        require(!p.executed, "DAOExecutor: already executed");
        require(!p.cancelled, "DAOExecutor: cancelled");
        require(block.timestamp >= p.eta, "DAOExecutor: timelock active");

        p.executed = true;
        ++executedCount;

        (bool success,) = p.target.call(p.callData);
        emit ProposalExecuted(proposalId, p.target, success, loopID);
    }

    // ── View helpers ───────────────────────────────────────────────────────────

    function _firstReadyProposal() internal view returns (uint256) {
        for (uint256 i = 0; i < proposalQueue.length; i++) {
            uint256 id = proposalQueue[i];
            Proposal storage p = proposals[id];
            if (!p.executed && !p.cancelled && block.timestamp >= p.eta) {
                return id;
            }
        }
        return type(uint256).max;
    }

    function pendingProposalCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < proposalQueue.length; i++) {
            Proposal storage p = proposals[proposalQueue[i]];
            if (!p.executed && !p.cancelled) count++;
        }
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setCheckInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "DAOExecutor: interval=0");
        checkInterval = _interval;
    }

    receive() external payable {}
}
