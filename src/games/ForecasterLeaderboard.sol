// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopCompatible.sol";
import "../AutoLoopRegistrar.sol";

interface IKaijuOracle {
    struct Round {
        uint256 commitEndAt;
        uint256 revealEndAt;
        uint256 targetClashId;
        uint256 totalPot;
        uint256 winningTotalStake;
        uint256 winningKaijuId;
        bool settled;
    }
    function getRound(uint256 roundId) external view returns (Round memory);
    function getRoundParticipantCount(uint256 roundId) external view returns (uint256);
    function getRoundParticipant(uint256 roundId, uint256 index) external view returns (address);
    function revealedKaijus(uint256 roundId, address player) external view returns (uint256);
    function currentRoundId() external view returns (uint256);
    function KAIJU_UNREVEALED() external view returns (uint256);
}

/**
 * @title ForecasterLeaderboard (Prediction Accuracy Tracker)
 * @author LuckyMachines LLC
 * @notice The third contract in the KaijuLeague → KaijuOracle → ForecasterLeaderboard
 *         chain. Reads settled KaijuOracle rounds, tracks per-address prediction
 *         accuracy across seasons, and distributes a prize pool to the top N
 *         forecasters at the end of each season.
 *
 *         AutoLoop fires once per season (configurable interval, e.g. 1 week).
 *         Each tick: process all settled KaijuOracle rounds since last season,
 *         update accuracy stats, distribute prizes to top N, open next season.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Four independent reasons:
 *
 *      1. ADVERSARIAL DISTRIBUTION TIMING. A forecaster in 2nd place wants to
 *         delay distribution until they accumulate more correct predictions. A
 *         forecaster in 1st place wants it now. No player-controlled trigger is
 *         neutral.
 *
 *      2. CROSS-CONTRACT 3-HOP DEPENDENCY. Distribution requires iterating
 *         KaijuOracle rounds which in turn depend on KaijuLeague's clash
 *         outcomes. Any player could trigger distribution after a favorable
 *         round before rivals have committed to the next round.
 *
 *      3. FREE-RIDER ON PROCESSING GAS. Processing many rounds costs gas.
 *         Each individual forecaster prefers to let someone else pay while
 *         waiting to see if they accumulate enough correct predictions.
 *
 *      4. PRIZE-POOL TIMING ATTACK. If a forecaster can trigger distribution,
 *         they can pick a block where they have the most favorable rank, or
 *         choose to fire before a rival's late-round reveal is included.
 *
 * @dev SEASON MODEL
 *      - Each season spans `distributionInterval` seconds.
 *      - On each distribution tick, at most `maxRoundsPerTick` oracle rounds
 *        are processed for accuracy scoring.
 *      - Top `topN` forecasters by season-correct-predictions share the prize
 *        pool equally. Ties broken by lifetime correct predictions.
 *      - Unclaimed prizes remain claimable by address indefinitely.
 *      - After distribution, season counters reset and a new season opens.
 *
 * @dev REVENUE MODEL
 *      - protocolRakeBps on each prize pool distribution → protocolFeeBalance
 *      - Anyone can fund the prize pool via fundPrizePool() or direct ETH send
 */
contract ForecasterLeaderboard is AutoLoopCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event SeasonClosed(
        uint256 indexed season,
        uint256 prizeDistributed,
        uint256 winnersCount,
        uint256 roundsProcessed
    );
    event PrizeClaimed(
        address indexed forecaster,
        uint256 indexed season,
        uint256 amount
    );
    event ScoreUpdated(
        address indexed forecaster,
        uint256 indexed roundId,
        bool correct
    );
    event PrizePoolFunded(address indexed from, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    IKaijuOracle public immutable kaijuOracle;
    uint256 public immutable distributionInterval;
    uint256 public immutable topN;
    uint256 public immutable maxRoundsPerTick;
    uint256 public immutable protocolRakeBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ===============================================================
    //  State
    // ===============================================================

    struct ForecasterStats {
        uint256 lifetimeCorrect;
        uint256 lifetimeTotal;
        uint256 lifetimeWinnings;
        uint256 seasonCorrect;
        uint256 seasonTotal;
    }

    mapping(address => ForecasterStats) public stats;
    address[] public allForecasters;
    mapping(address => bool) public isTracked;

    /// @dev Pull-payment prizes per season.
    mapping(uint256 => mapping(address => uint256)) public seasonPrizes;
    mapping(uint256 => mapping(address => bool)) public seasonClaimed;

    uint256 public lastProcessedRoundId;
    uint256 public nextDistributionAt;
    uint256 public currentSeason;
    uint256 public prizePool;
    uint256 public protocolFeeBalance;
    uint256 public totalSeasonsCompleted;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        address _kaijuOracle,
        uint256 _distributionInterval,
        uint256 _topN,
        uint256 _maxRoundsPerTick,
        uint256 _protocolRakeBps
    ) {
        require(_kaijuOracle != address(0), "ForecasterLeaderboard: oracle=0");
        require(_distributionInterval > 0, "ForecasterLeaderboard: interval=0");
        require(_topN > 0 && _topN <= 10, "ForecasterLeaderboard: topN range");
        require(_maxRoundsPerTick > 0, "ForecasterLeaderboard: maxRounds=0");
        require(_protocolRakeBps <= 2000, "ForecasterLeaderboard: rake > 20%");

        kaijuOracle = IKaijuOracle(_kaijuOracle);
        distributionInterval = _distributionInterval;
        topN = _topN;
        maxRoundsPerTick = _maxRoundsPerTick;
        protocolRakeBps = _protocolRakeBps;
        currentSeason = 1;
        nextDistributionAt = block.timestamp + _distributionInterval;

        // Don't backfill pre-deployment oracle rounds
        uint256 oracleRound = kaijuOracle.currentRoundId();
        lastProcessedRoundId = oracleRound > 0 ? oracleRound - 1 : 0;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  AutoLoop Hooks
    // ===============================================================

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = block.timestamp >= nextDistributionAt;
        progressWithData = abi.encode(currentSeason);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        uint256 season = abi.decode(progressWithData, (uint256));
        require(season == currentSeason, "ForecasterLeaderboard: stale season");
        require(block.timestamp >= nextDistributionAt, "ForecasterLeaderboard: too soon");

        // ---- Step 1: Process settled oracle rounds ----
        uint256 oracleCurrent = kaijuOracle.currentRoundId();
        // currentRoundId in oracle is the OPEN round; settled rounds are 1..currentRoundId-1
        uint256 latestSettled = oracleCurrent > 1 ? oracleCurrent - 1 : 0;

        uint256 roundsProcessed = 0;
        for (
            uint256 rid = lastProcessedRoundId + 1;
            rid <= latestSettled && roundsProcessed < maxRoundsPerTick;
            rid++
        ) {
            IKaijuOracle.Round memory r = kaijuOracle.getRound(rid);
            if (!r.settled) {
                lastProcessedRoundId = rid;
                roundsProcessed++;
                continue;
            }

            uint256 winningKaijuId = r.winningKaijuId;
            uint256 participantCount = kaijuOracle.getRoundParticipantCount(rid);

            for (uint256 i = 0; i < participantCount; i++) {
                address forecaster = kaijuOracle.getRoundParticipant(rid, i);
                uint256 revealed = kaijuOracle.revealedKaijus(rid, forecaster);

                // Skip players who committed but never revealed
                if (revealed == kaijuOracle.KAIJU_UNREVEALED()) continue;

                if (!isTracked[forecaster]) {
                    isTracked[forecaster] = true;
                    allForecasters.push(forecaster);
                }

                ForecasterStats storage s = stats[forecaster];
                s.lifetimeTotal++;
                s.seasonTotal++;
                bool correct = (winningKaijuId != 0 && revealed == winningKaijuId);
                if (correct) {
                    s.lifetimeCorrect++;
                    s.seasonCorrect++;
                }
                emit ScoreUpdated(forecaster, rid, correct);
            }

            lastProcessedRoundId = rid;
            roundsProcessed++;
        }

        // ---- Step 2: Distribute prize pool to top N ----
        uint256 rake = (prizePool * protocolRakeBps) / BPS_DENOMINATOR;
        uint256 distributable = prizePool > rake ? prizePool - rake : 0;
        protocolFeeBalance += rake;
        prizePool = 0;

        uint256 distributed = 0;
        uint256 winnersCount = 0;

        if (distributable > 0) {
            (address[] memory topForecasters, uint256 found) = _findTopN(topN);
            if (found > 0) {
                uint256 share = distributable / found;
                for (uint256 i = 0; i < found; i++) {
                    address winner = topForecasters[i];
                    seasonPrizes[season][winner] += share;
                    stats[winner].lifetimeWinnings += share;
                    distributed += share;
                    winnersCount++;
                }
                // Dust (rounding remainder) goes to protocol
                protocolFeeBalance += distributable - distributed;
            } else {
                // No qualified forecasters this season
                protocolFeeBalance += distributable;
            }
        }

        emit SeasonClosed(season, distributed, winnersCount, roundsProcessed);

        // ---- Step 3: Reset season counters ----
        uint256 total = allForecasters.length;
        for (uint256 i = 0; i < total; i++) {
            stats[allForecasters[i]].seasonCorrect = 0;
            stats[allForecasters[i]].seasonTotal = 0;
        }

        // ---- Step 4: Open next season ----
        currentSeason++;
        totalSeasonsCompleted++;
        nextDistributionAt = block.timestamp + distributionInterval;
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Claim prize from a prior season.
    function claimSeasonPrize(uint256 season) external {
        require(!seasonClaimed[season][_msgSender()], "ForecasterLeaderboard: already claimed");
        uint256 amount = seasonPrizes[season][_msgSender()];
        require(amount > 0, "ForecasterLeaderboard: no prize");
        seasonClaimed[season][_msgSender()] = true;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "ForecasterLeaderboard: transfer failed");
        emit PrizeClaimed(_msgSender(), season, amount);
    }

    /// @notice Fund the prize pool for the current season.
    function fundPrizePool() external payable {
        require(msg.value > 0, "ForecasterLeaderboard: amount=0");
        prizePool += msg.value;
        emit PrizePoolFunded(_msgSender(), msg.value);
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getStats(address forecaster) external view returns (ForecasterStats memory) {
        return stats[forecaster];
    }

    function forecasterCount() external view returns (uint256) {
        return allForecasters.length;
    }

    // ===============================================================
    //  Admin
    // ===============================================================

    function withdrawProtocolFees(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "ForecasterLeaderboard: zero address");
        require(amount <= protocolFeeBalance, "ForecasterLeaderboard: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "ForecasterLeaderboard: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    // ===============================================================
    //  Internal
    // ===============================================================

    /// @dev O(n * topN) selection sort returning the top N forecasters by
    ///      seasonCorrect (≥1). Ties broken by lifetimeCorrect.
    ///      Safe for demo-scale forecaster counts (< a few hundred).
    function _findTopN(
        uint256 n
    ) internal view returns (address[] memory result, uint256 found) {
        uint256 total = allForecasters.length;
        result = new address[](n < total ? n : total);
        bool[] memory used = new bool[](total);
        found = 0;

        for (uint256 slot = 0; slot < n; slot++) {
            uint256 bestSeason = 0;
            uint256 bestLifetime = 0;
            uint256 bestIdx = type(uint256).max;

            for (uint256 i = 0; i < total; i++) {
                if (used[i]) continue;
                ForecasterStats storage s = stats[allForecasters[i]];
                if (s.seasonTotal == 0) continue; // didn't participate this season
                if (s.seasonCorrect == 0) continue; // no correct predictions

                bool better = false;
                if (bestIdx == type(uint256).max) {
                    better = true;
                } else if (s.seasonCorrect > bestSeason) {
                    better = true;
                } else if (s.seasonCorrect == bestSeason && s.lifetimeCorrect > bestLifetime) {
                    better = true;
                }

                if (better) {
                    bestSeason = s.seasonCorrect;
                    bestLifetime = s.lifetimeCorrect;
                    bestIdx = i;
                }
            }

            if (bestIdx == type(uint256).max) break; // no more qualified forecasters

            result[found] = allForecasters[bestIdx];
            used[bestIdx] = true;
            found++;
        }
    }

    /// @notice Direct ETH sends add to prize pool.
    receive() external payable {
        prizePool += msg.value;
        emit PrizePoolFunded(_msgSender(), msg.value);
    }
}
