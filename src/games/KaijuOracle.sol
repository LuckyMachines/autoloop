// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopCompatible.sol";
import "../AutoLoopRegistrar.sol";

interface IKaijuLeague {
    function currentClashId() external view returns (uint256);
    function clashWinners(uint256 clashId) external view returns (uint256);
}

/**
 * @title KaijuOracle (Clash Prediction Market)
 * @author LuckyMachines LLC
 * @notice A commit-reveal prediction market layered on top of KaijuLeague.
 *         Before each clash, players commit to which kaiju they believe will
 *         win. After the commit window closes, players reveal their prediction.
 *         AutoLoop settles the round once the target clash has resolved in
 *         KaijuLeague and the reveal window is over. Correct predictors split
 *         the pot proportionally to stake.
 *
 *         KaijuOracle is the middle contract in a 3-contract AutoLoop chain:
 *         KaijuLeague → KaijuOracle → ForecasterLeaderboard.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Three independent reasons, any one of which is sufficient:
 *
 *      1. COMMIT-REVEAL INTEGRITY. Reveal must happen STRICTLY BEFORE
 *         settlement. A player-controlled trigger could fire mid-reveal-phase
 *         after seeing opponents' choices, destroying the commit's guarantee.
 *
 *      2. ADVERSARIAL MULTI-PARTY. Players on a popular kaiju want delayed
 *         settlement. Players on a minority kaiju want it fast. No
 *         player-controlled trigger is neutral.
 *
 *      3. CROSS-CONTRACT COORDINATION. Settlement requires BOTH the reveal
 *         window to be over AND the target clash to have resolved in
 *         KaijuLeague. A self-interested player could fire settlement the
 *         instant the clash resolves, before all reveals are in. AutoLoop's
 *         cadence guarantees the full reveal window always completes first.
 *
 * @dev PARTICIPANT TRACKING
 *      To support ForecasterLeaderboard, every player who commits is added to
 *      roundParticipants[roundId]. This lets the leaderboard iterate over all
 *      participants without off-chain indexing.
 *
 * @dev REVENUE MODEL
 *      - protocolRakeBps on every round pot      → protocolFeeBalance
 *      - Forfeited stakes (unrevealed commits)    → round pot for winners
 *      - Rounds with no correct predictors        → entire pot to protocol
 */
contract KaijuOracle is AutoLoopCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event RoundOpened(
        uint256 indexed roundId,
        uint256 indexed targetClashId,
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
        uint256 kaijuId
    );
    event RoundSettled(
        uint256 indexed roundId,
        uint256 indexed winningKaijuId,
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
    uint256 public constant KAIJU_UNREVEALED = 0;

    IKaijuLeague public immutable kaijuLeague;
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
        uint256 targetClashId;
        uint256 totalPot;
        uint256 winningTotalStake;
        uint256 winningKaijuId;
        bool settled;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => bytes32)) public commits;
    mapping(uint256 => mapping(address => uint256)) public stakes;
    /// @dev 0 = unrevealed. Valid kaiju IDs start at 1 in KaijuLeague.
    mapping(uint256 => mapping(address => uint256)) public revealedKaijus;
    mapping(uint256 => mapping(address => bool)) public claimed;
    /// @dev Aggregates for eager win-share computation. Updated on reveal.
    mapping(uint256 => mapping(uint256 => uint256)) public revealedTotalPerKaiju;
    mapping(uint256 => mapping(uint256 => uint256)) public revealedCountPerKaiju;
    /// @dev All players who committed in a round (for ForecasterLeaderboard).
    mapping(uint256 => address[]) public roundParticipants;

    uint256 public currentRoundId;
    uint256 public protocolFeeBalance;
    uint256 public totalRoundsSettled;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        address _kaijuLeague,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _minStake,
        uint256 _protocolRakeBps
    ) {
        require(_kaijuLeague != address(0), "KaijuOracle: league=0");
        require(_commitDuration > 0, "KaijuOracle: commit=0");
        require(_revealDuration > 0, "KaijuOracle: reveal=0");
        require(_minStake > 0, "KaijuOracle: stake=0");
        require(_protocolRakeBps <= 2000, "KaijuOracle: rake > 20%");
        kaijuLeague = IKaijuLeague(_kaijuLeague);
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
     * @notice Lock in a kaiju prediction for the current round.
     * @param commitHash keccak256(abi.encode(kaijuId, salt, msg.sender))
     */
    function commit(bytes32 commitHash) external payable {
        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp < r.commitEndAt,
            "KaijuOracle: commit phase over"
        );
        require(msg.value >= minStake, "KaijuOracle: stake too low");
        require(
            commits[currentRoundId][_msgSender()] == bytes32(0),
            "KaijuOracle: already committed"
        );
        require(commitHash != bytes32(0), "KaijuOracle: empty commit");

        commits[currentRoundId][_msgSender()] = commitHash;
        stakes[currentRoundId][_msgSender()] = msg.value;
        r.totalPot += msg.value;
        roundParticipants[currentRoundId].push(_msgSender());

        emit Committed(currentRoundId, _msgSender(), msg.value, commitHash);
    }

    /**
     * @notice Reveal a prior commit during the reveal window.
     * @param kaijuId The kaiju ID you predicted would win the clash.
     * @param salt    The salt used when computing the commit hash.
     */
    function reveal(uint256 kaijuId, bytes32 salt) external {
        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp >= r.commitEndAt,
            "KaijuOracle: still commit phase"
        );
        require(
            block.timestamp < r.revealEndAt,
            "KaijuOracle: reveal phase over"
        );
        require(kaijuId > 0, "KaijuOracle: invalid kaiju");
        require(
            revealedKaijus[currentRoundId][_msgSender()] == KAIJU_UNREVEALED,
            "KaijuOracle: already revealed"
        );

        bytes32 expected = keccak256(abi.encode(kaijuId, salt, _msgSender()));
        require(
            commits[currentRoundId][_msgSender()] == expected,
            "KaijuOracle: bad reveal"
        );

        revealedKaijus[currentRoundId][_msgSender()] = kaijuId;
        uint256 playerStake = stakes[currentRoundId][_msgSender()];
        revealedTotalPerKaiju[currentRoundId][kaijuId] += playerStake;
        revealedCountPerKaiju[currentRoundId][kaijuId] += 1;

        emit Revealed(currentRoundId, _msgSender(), kaijuId);
    }

    /**
     * @notice Claim winnings from a settled round.
     */
    function claimWinnings(uint256 roundId) external {
        Round storage r = rounds[roundId];
        require(r.settled, "KaijuOracle: not settled");
        require(!claimed[roundId][_msgSender()], "KaijuOracle: already claimed");
        require(
            revealedKaijus[roundId][_msgSender()] == r.winningKaijuId,
            "KaijuOracle: not a winner"
        );

        uint256 stake = stakes[roundId][_msgSender()];
        uint256 winningStake = r.winningTotalStake;
        require(winningStake > 0, "KaijuOracle: no pot");

        uint256 totalPotAfterRake = r.totalPot -
            (r.totalPot * protocolRakeBps) / BPS_DENOMINATOR;
        uint256 share = (totalPotAfterRake * stake) / winningStake;

        claimed[roundId][_msgSender()] = true;
        (bool sent, ) = _msgSender().call{value: share}("");
        require(sent, "KaijuOracle: claim failed");
        emit WinningsClaimed(roundId, _msgSender(), share);
    }

    // ===============================================================
    //  AutoLoop Hooks
    // ===============================================================

    /**
     * @notice Ready when reveal window is over, round is unsettled, and
     *         the target clash has resolved in KaijuLeague.
     */
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        Round storage r = rounds[currentRoundId];
        uint256 clashWinnerId = kaijuLeague.clashWinners(r.targetClashId);
        loopIsReady =
            block.timestamp >= r.revealEndAt &&
            !r.settled &&
            clashWinnerId != 0;
        progressWithData = abi.encode(currentRoundId);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        uint256 roundId = abi.decode(progressWithData, (uint256));
        require(roundId == currentRoundId, "KaijuOracle: stale round");

        Round storage r = rounds[currentRoundId];
        require(block.timestamp >= r.revealEndAt, "KaijuOracle: reveal open");
        require(!r.settled, "KaijuOracle: already settled");

        uint256 clashWinnerId = kaijuLeague.clashWinners(r.targetClashId);
        require(clashWinnerId != 0, "KaijuOracle: clash not resolved");

        r.winningKaijuId = clashWinnerId;
        r.winningTotalStake = revealedTotalPerKaiju[currentRoundId][clashWinnerId];

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
                clashWinnerId,
                r.totalPot,
                protocolCut,
                revealedCountPerKaiju[currentRoundId][clashWinnerId]
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

    function getRoundParticipantCount(uint256 roundId) external view returns (uint256) {
        return roundParticipants[roundId].length;
    }

    function getRoundParticipant(uint256 roundId, uint256 index) external view returns (address) {
        return roundParticipants[roundId][index];
    }

    // ===============================================================
    //  Admin
    // ===============================================================

    function withdrawProtocolFees(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "KaijuOracle: zero address");
        require(amount <= protocolFeeBalance, "KaijuOracle: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "KaijuOracle: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    // ===============================================================
    //  Internal
    // ===============================================================

    function _openRound() internal {
        currentRoundId++;
        Round storage r = rounds[currentRoundId];
        r.targetClashId = kaijuLeague.currentClashId();
        r.commitEndAt = block.timestamp + commitDuration;
        r.revealEndAt = r.commitEndAt + revealDuration;
        emit RoundOpened(currentRoundId, r.targetClashId, r.commitEndAt, r.revealEndAt);
    }

    receive() external payable {}
}
