// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopCompatible.sol";
import "../AutoLoopRegistrar.sol";

interface IGladiatorArena {
    function currentBoutId() external view returns (uint256);
    function boutWinners(uint256 boutId) external view returns (uint256);
}

/**
 * @title GladiatorOracle (Bout Prediction Market)
 * @author LuckyMachines LLC
 * @notice A commit-reveal prediction market layered on top of GladiatorArena.
 *         Before each bout, players commit to which gladiator they believe will
 *         win. After the commit window closes, players reveal their prediction.
 *         AutoLoop settles the round once the target bout has resolved in
 *         GladiatorArena and the reveal window is over. Correct predictors
 *         split the pot proportionally to stake.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Three independent reasons, any one of which is sufficient:
 *
 *      1. COMMIT-REVEAL INTEGRITY. Reveal must happen STRICTLY BEFORE
 *         settlement. If any player could trigger settlement, they could do so
 *         mid-reveal-phase after seeing opponents' choices but before their own,
 *         destroying the cryptographic guarantee of the commit. A neutral
 *         scheduler is the only way to preserve this invariant.
 *
 *      2. ADVERSARIAL MULTI-PARTY. Players who committed to a popular gladiator
 *         want delayed settlement (hoping fewer rivals reveal). Players who
 *         committed to a minority gladiator want fast settlement. No
 *         player-controlled trigger is neutral.
 *
 *      3. CROSS-CONTRACT COORDINATION. Settlement requires BOTH the reveal
 *         window to be over AND the target bout to have resolved in
 *         GladiatorArena. A self-interested player could trigger settlement the
 *         instant the bout resolves, before all reveals are in. AutoLoop's
 *         cadence guarantees the full reveal window always completes first.
 *
 *      This is the cross-contract demo in the stack: GladiatorOracle literally
 *      reads GladiatorArena and cannot settle without a neutral scheduler that
 *      respects both timing constraints simultaneously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - protocolRakeBps on every round pot      → protocolFeeBalance
 *      - Forfeited stakes (unrevealed commits)    → round pot for winners
 *      - Rounds with no correct predictors        → entire pot to protocol
 */
contract GladiatorOracle is AutoLoopCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event RoundOpened(
        uint256 indexed roundId,
        uint256 indexed targetBoutId,
        uint256 commitEndAt,
        uint256 revealEndAt
    );
    event Committed(
        uint256 indexed roundId,
        address indexed player,
        uint256 stake,
        bytes32 commitHash
    );
    event Revealed(
        uint256 indexed roundId,
        address indexed player,
        uint256 gladiatorId
    );
    event RoundSettled(
        uint256 indexed roundId,
        uint256 indexed winningGladiatorId,
        uint256 totalPot,
        uint256 protocolFee,
        uint256 winnerCount
    );
    event RoundNoWinners(uint256 indexed roundId, uint256 potForfeited);
    event WinningsClaimed(
        uint256 indexed roundId,
        address indexed winner,
        uint256 amount
    );
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration
    // ===============================================================

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant GLADIATOR_UNREVEALED = 0;

    IGladiatorArena public immutable gladiatorArena;
    uint256 public immutable commitDuration;
    uint256 public immutable revealDuration;
    uint256 public immutable minStake;
    uint256 public immutable protocolRakeBps;

    // ===============================================================
    //  State
    // ===============================================================

    struct Round {
        uint256 commitEndAt;
        uint256 revealEndAt;
        uint256 targetBoutId;
        uint256 totalPot;
        uint256 winningTotalStake;
        uint256 winningGladiatorId;
        bool settled;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => bytes32)) public commits;
    mapping(uint256 => mapping(address => uint256)) public stakes;
    /// @dev 0 = unrevealed. Valid gladiator IDs start at 1.
    mapping(uint256 => mapping(address => uint256)) public revealedGladiators;
    mapping(uint256 => mapping(address => bool)) public claimed;
    /// @dev Aggregates for eager win-share computation. Updated on reveal.
    mapping(uint256 => mapping(uint256 => uint256)) public revealedTotalPerGladiator;
    mapping(uint256 => mapping(uint256 => uint256)) public revealedCountPerGladiator;

    uint256 public currentRoundId;
    uint256 public protocolFeeBalance;
    uint256 public totalRoundsSettled;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        address _gladiatorArena,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _minStake,
        uint256 _protocolRakeBps
    ) {
        require(_gladiatorArena != address(0), "GladiatorOracle: arena=0");
        require(_commitDuration > 0, "GladiatorOracle: commit=0");
        require(_revealDuration > 0, "GladiatorOracle: reveal=0");
        require(_minStake > 0, "GladiatorOracle: stake=0");
        require(_protocolRakeBps <= 2000, "GladiatorOracle: rake > 20%");
        gladiatorArena = IGladiatorArena(_gladiatorArena);
        commitDuration = _commitDuration;
        revealDuration = _revealDuration;
        minStake = _minStake;
        protocolRakeBps = _protocolRakeBps;
        _openRound();
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /**
     * @notice Lock in a gladiator prediction for the current round.
     * @param commitHash keccak256(abi.encode(gladiatorId, salt, msg.sender))
     */
    function commit(bytes32 commitHash) external payable {
        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp < r.commitEndAt,
            "GladiatorOracle: commit phase over"
        );
        require(msg.value >= minStake, "GladiatorOracle: stake too low");
        require(
            commits[currentRoundId][_msgSender()] == bytes32(0),
            "GladiatorOracle: already committed"
        );
        require(commitHash != bytes32(0), "GladiatorOracle: empty commit");

        commits[currentRoundId][_msgSender()] = commitHash;
        stakes[currentRoundId][_msgSender()] = msg.value;
        r.totalPot += msg.value;

        emit Committed(currentRoundId, _msgSender(), msg.value, commitHash);
    }

    /**
     * @notice Reveal a prior commit during the reveal window.
     * @param gladiatorId The gladiator ID you predicted would win.
     * @param salt        The salt used when computing the commit hash.
     */
    function reveal(uint256 gladiatorId, bytes32 salt) external {
        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp >= r.commitEndAt,
            "GladiatorOracle: still commit phase"
        );
        require(
            block.timestamp < r.revealEndAt,
            "GladiatorOracle: reveal phase over"
        );
        require(gladiatorId > 0, "GladiatorOracle: invalid gladiator");
        require(
            revealedGladiators[currentRoundId][_msgSender()] == GLADIATOR_UNREVEALED,
            "GladiatorOracle: already revealed"
        );

        bytes32 expected = keccak256(abi.encode(gladiatorId, salt, _msgSender()));
        require(
            commits[currentRoundId][_msgSender()] == expected,
            "GladiatorOracle: bad reveal"
        );

        revealedGladiators[currentRoundId][_msgSender()] = gladiatorId;
        uint256 playerStake = stakes[currentRoundId][_msgSender()];
        revealedTotalPerGladiator[currentRoundId][gladiatorId] += playerStake;
        revealedCountPerGladiator[currentRoundId][gladiatorId] += 1;

        emit Revealed(currentRoundId, _msgSender(), gladiatorId);
    }

    /**
     * @notice Claim winnings from a settled round.
     */
    function claimWinnings(uint256 roundId) external {
        Round storage r = rounds[roundId];
        require(r.settled, "GladiatorOracle: not settled");
        require(
            !claimed[roundId][_msgSender()],
            "GladiatorOracle: already claimed"
        );
        require(
            revealedGladiators[roundId][_msgSender()] == r.winningGladiatorId,
            "GladiatorOracle: not a winner"
        );

        uint256 stake = stakes[roundId][_msgSender()];
        uint256 winningStake = r.winningTotalStake;
        require(winningStake > 0, "GladiatorOracle: no pot");

        uint256 totalPotAfterRake = r.totalPot -
            (r.totalPot * protocolRakeBps) / BPS_DENOMINATOR;
        uint256 share = (totalPotAfterRake * stake) / winningStake;

        claimed[roundId][_msgSender()] = true;
        (bool sent, ) = _msgSender().call{value: share}("");
        require(sent, "GladiatorOracle: claim failed");
        emit WinningsClaimed(roundId, _msgSender(), share);
    }

    // ===============================================================
    //  AutoLoop Hooks
    // ===============================================================

    /**
     * @notice Ready when reveal window is over, round is unsettled, and
     *         the target bout has resolved in GladiatorArena.
     */
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        Round storage r = rounds[currentRoundId];
        uint256 boutWinnerId = gladiatorArena.boutWinners(r.targetBoutId);
        loopIsReady =
            block.timestamp >= r.revealEndAt &&
            !r.settled &&
            boutWinnerId != 0;
        progressWithData = abi.encode(currentRoundId);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        uint256 roundId = abi.decode(progressWithData, (uint256));
        require(roundId == currentRoundId, "GladiatorOracle: stale round");

        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp >= r.revealEndAt,
            "GladiatorOracle: reveal open"
        );
        require(!r.settled, "GladiatorOracle: already settled");

        uint256 boutWinnerId = gladiatorArena.boutWinners(r.targetBoutId);
        require(boutWinnerId != 0, "GladiatorOracle: bout not resolved");

        r.winningGladiatorId = boutWinnerId;
        r.winningTotalStake = revealedTotalPerGladiator[currentRoundId][boutWinnerId];

        uint256 protocolCut = (r.totalPot * protocolRakeBps) / BPS_DENOMINATOR;
        protocolFeeBalance += protocolCut;
        r.settled = true;

        if (r.winningTotalStake == 0) {
            uint256 forfeited = r.totalPot - protocolCut;
            protocolFeeBalance += forfeited;
            emit RoundNoWinners(currentRoundId, r.totalPot);
        } else {
            emit RoundSettled(
                currentRoundId,
                boutWinnerId,
                r.totalPot,
                protocolCut,
                revealedCountPerGladiator[currentRoundId][boutWinnerId]
            );
        }

        totalRoundsSettled++;
        _openRound();
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getRound(uint256 roundId) external view returns (Round memory) {
        return rounds[roundId];
    }

    // ===============================================================
    //  Admin
    // ===============================================================

    function withdrawProtocolFees(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "GladiatorOracle: zero address");
        require(
            amount <= protocolFeeBalance,
            "GladiatorOracle: exceeds balance"
        );
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "GladiatorOracle: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    // ===============================================================
    //  Internal
    // ===============================================================

    function _openRound() internal {
        currentRoundId++;
        Round storage r = rounds[currentRoundId];
        r.targetBoutId = gladiatorArena.currentBoutId();
        r.commitEndAt = block.timestamp + commitDuration;
        r.revealEndAt = r.commitEndAt + revealDuration;
        emit RoundOpened(
            currentRoundId,
            r.targetBoutId,
            r.commitEndAt,
            r.revealEndAt
        );
    }

    receive() external payable {}
}
