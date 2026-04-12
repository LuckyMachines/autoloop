// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title PhantomDriver (Commit-Reveal MVP Bet)
 * @author LuckyMachines LLC
 * @notice A multi-party commit-reveal prediction market: players bet on
 *         which of four driver archetypes will be named MVP in the next
 *         autonomous race round. The MVP is chosen by VRF on a fixed
 *         schedule after the reveal window closes. Correct predictors
 *         split the pot; forfeited and losing stakes fund the winners.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Three independent reasons, any one of which is sufficient:
 *
 *      1. COMMIT-REVEAL INTEGRITY. The whole point of commit-reveal is that
 *         reveal happens STRICTLY BEFORE resolution. If any player could
 *         trigger resolution, they could resolve mid-reveal-phase after
 *         seeing some opponents' reveals but before their own — letting
 *         them withhold or broadcast based on live information. A neutral
 *         scheduler is cryptographically necessary.
 *
 *      2. ADVERSARIAL MULTI-PARTY. Each role's bettors want a different
 *         trigger time. Bettors who know their opponents have over-revealed
 *         on a popular role want to delay resolution (more time for the
 *         VRF to maybe favor them). Bettors on minority roles want fast
 *         resolution. No player-controlled trigger is neutral.
 *
 *      3. FORFEIT FREE-RIDER. If you made a commit but never revealed,
 *         your funds go to the pot. Other players would love to close
 *         the reveal window the second before you'd have revealed. With
 *         a fixed block-cadence trigger nobody gets that choice.
 *
 *      This is the sharpest commit-reveal demo in the stack: the
 *      cryptographic pattern IS the game, and it literally cannot work
 *      without a neutral resolver.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - protocolRakeBps on every round pot      → protocolFeeBalance
 *      - Forfeited commits (never revealed)      → round pot for winners
 *      - Rounds with no winners                   → entire pot to protocol
 */
contract PhantomDriver is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event RoundOpened(
        uint256 indexed roundId,
        uint256 commitEndAt,
        uint256 revealEndAt
    );
    event Committed(
        uint256 indexed roundId,
        address indexed player,
        uint256 stake,
        bytes32 commit
    );
    event Revealed(
        uint256 indexed roundId,
        address indexed player,
        uint8 role
    );
    event RoundResolved(
        uint256 indexed roundId,
        uint8 winningRole,
        uint256 totalPot,
        uint256 protocolFee,
        uint256 winnerCount,
        bytes32 randomness
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

    uint8 public constant NUM_ROLES = 4;
    uint8 public constant ROLE_UNREVEALED = 255;
    uint256 public constant BPS_DENOMINATOR = 10_000;

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
        uint256 totalPot;
        uint256 winningTotalStake; // sum of stakes of correct revealers
        uint8 winningRole;
        bool resolved;
    }

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => bytes32)) public commits;
    mapping(uint256 => mapping(address => uint256)) public stakes;
    mapping(uint256 => mapping(address => uint8)) public revealedRoles;
    mapping(uint256 => mapping(address => bool)) public claimed;

    uint256 public currentRoundId;
    uint256 public protocolFeeBalance;
    uint256 public totalRoundsResolved;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _minStake,
        uint256 _protocolRakeBps
    ) {
        require(_commitDuration > 0, "PhantomDriver: commit=0");
        require(_revealDuration > 0, "PhantomDriver: reveal=0");
        require(_minStake > 0, "PhantomDriver: stake=0");
        require(_protocolRakeBps <= 2000, "PhantomDriver: rake > 20%");
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
     * @notice Commit to a role prediction for the current round.
     * @param commitHash keccak256(abi.encode(role, salt, msg.sender))
     */
    function commit(bytes32 commitHash) external payable {
        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp < r.commitEndAt,
            "PhantomDriver: commit phase over"
        );
        require(msg.value >= minStake, "PhantomDriver: stake too low");
        require(
            commits[currentRoundId][_msgSender()] == bytes32(0),
            "PhantomDriver: already committed"
        );
        require(commitHash != bytes32(0), "PhantomDriver: empty commit");

        commits[currentRoundId][_msgSender()] = commitHash;
        stakes[currentRoundId][_msgSender()] = msg.value;
        revealedRoles[currentRoundId][_msgSender()] = ROLE_UNREVEALED;
        r.totalPot += msg.value;

        emit Committed(currentRoundId, _msgSender(), msg.value, commitHash);
    }

    /**
     * @notice Reveal a prior commit during the reveal window.
     * @param role  The role you committed to (0..NUM_ROLES-1).
     * @param salt  The salt used in the commit.
     */
    function reveal(uint8 role, bytes32 salt) external {
        Round storage r = rounds[currentRoundId];
        require(
            block.timestamp >= r.commitEndAt,
            "PhantomDriver: still commit phase"
        );
        require(
            block.timestamp < r.revealEndAt,
            "PhantomDriver: reveal phase over"
        );
        require(role < NUM_ROLES, "PhantomDriver: bad role");
        require(
            revealedRoles[currentRoundId][_msgSender()] == ROLE_UNREVEALED,
            "PhantomDriver: already revealed"
        );

        bytes32 expected = keccak256(abi.encode(role, salt, _msgSender()));
        require(
            commits[currentRoundId][_msgSender()] == expected,
            "PhantomDriver: bad reveal"
        );

        revealedRoles[currentRoundId][_msgSender()] = role;
        // Aggregate for eager winning-share computation during resolution
        uint256 playerStake = stakes[currentRoundId][_msgSender()];
        revealedTotalPerRole[currentRoundId][role] += playerStake;
        revealedCountPerRole[currentRoundId][role] += 1;

        emit Revealed(currentRoundId, _msgSender(), role);
    }

    /**
     * @notice Claim winnings from a resolved round.
     */
    function claimWinnings(uint256 roundId) external {
        Round storage r = rounds[roundId];
        require(r.resolved, "PhantomDriver: not resolved");
        require(
            !claimed[roundId][_msgSender()],
            "PhantomDriver: already claimed"
        );
        require(
            revealedRoles[roundId][_msgSender()] == r.winningRole,
            "PhantomDriver: not a winner"
        );

        uint256 stake = stakes[roundId][_msgSender()];
        uint256 winningStake = r.winningTotalStake;
        require(winningStake > 0, "PhantomDriver: no pot");

        uint256 totalPotAfterRake = r.totalPot -
            (r.totalPot * protocolRakeBps) / BPS_DENOMINATOR;
        uint256 share = (totalPotAfterRake * stake) / winningStake;

        claimed[roundId][_msgSender()] = true;
        (bool sent, ) = _msgSender().call{value: share}("");
        require(sent, "PhantomDriver: claim failed");
        emit WinningsClaimed(roundId, _msgSender(), share);
    }

    // ===============================================================
    //  AutoLoop VRF Hooks
    // ===============================================================

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        Round storage r = rounds[currentRoundId];
        loopIsReady = block.timestamp >= r.revealEndAt && !r.resolved;
        progressWithData = abi.encode(_loopID);
    }

    function progressLoop(
        bytes calldata progressWithData
    ) external override {
        (bytes32 randomness, bytes memory gameData) = _verifyAndExtractRandomness(
            progressWithData,
            tx.origin
        );
        uint256 loopID = abi.decode(gameData, (uint256));
        _progressInternal(randomness, loopID);
    }

    function _progressInternal(
        bytes32 randomness,
        uint256 loopID
    ) internal {
        Round storage r = rounds[currentRoundId];
        require(loopID == _loopID, "PhantomDriver: stale loop id");
        require(
            block.timestamp >= r.revealEndAt,
            "PhantomDriver: reveal phase open"
        );
        require(!r.resolved, "PhantomDriver: already resolved");

        uint8 winningRole = uint8(uint256(randomness) % NUM_ROLES);
        r.winningRole = winningRole;
        r.resolved = true;

        // Scan revealed players once via events — on-chain bookkeeping
        // would require an additional list; instead we rely on an
        // aggregated sum that's updated lazily in claimWinnings via a
        // precomputed winningTotalStake computed eagerly here. We need
        // to know the total winning stake WITHOUT iterating the map,
        // which means we track per-role revealed totals.
        //
        // Since we don't know at commit time what the winning role will
        // be, we maintain totals for all 4 roles in revealedTotalPerRole
        // and select the winning one here. See commitAggregates mapping.
        r.winningTotalStake = revealedTotalPerRole[currentRoundId][winningRole];

        uint256 protocolCut = (r.totalPot * protocolRakeBps) /
            BPS_DENOMINATOR;
        protocolFeeBalance += protocolCut;

        if (r.winningTotalStake == 0) {
            // No winners — entire pot (minus rake already taken) goes to
            // protocol as forfeiture
            uint256 forfeited = r.totalPot - protocolCut;
            protocolFeeBalance += forfeited;
            emit RoundNoWinners(currentRoundId, r.totalPot);
        } else {
            emit RoundResolved(
                currentRoundId,
                winningRole,
                r.totalPot,
                protocolCut,
                revealedCountPerRole[currentRoundId][winningRole],
                randomness
            );
        }

        totalRoundsResolved++;
        ++_loopID;
        _openRound();
    }

    // ===============================================================
    //  Aggregates for eager computation of winning share
    //  (updated on reveal)
    // ===============================================================

    mapping(uint256 => mapping(uint8 => uint256)) public revealedTotalPerRole;
    mapping(uint256 => mapping(uint8 => uint256)) public revealedCountPerRole;

    // ===============================================================
    //  Views
    // ===============================================================

    function currentLoopID() external view returns (uint256) {
        return _loopID;
    }

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
        require(to != address(0), "PhantomDriver: zero address");
        require(
            amount <= protocolFeeBalance,
            "PhantomDriver: exceeds balance"
        );
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "PhantomDriver: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    // ===============================================================
    //  Internal
    // ===============================================================

    function _openRound() internal {
        currentRoundId++;
        Round storage r = rounds[currentRoundId];
        r.commitEndAt = block.timestamp + commitDuration;
        r.revealEndAt = r.commitEndAt + revealDuration;
        emit RoundOpened(
            currentRoundId,
            r.commitEndAt,
            r.revealEndAt
        );
    }

    receive() external payable {}
}
