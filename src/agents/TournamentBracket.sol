// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopVRFCompatible.sol";

/// @title TournamentBracket
/// @notice Single-elimination tournament with entry-fee prize pool. Players register, admin
///         starts the bracket, VRF resolves each round, champion takes the pot.
///         Self-triggering fails on two axes: (1) a losing player can delay the round that
///         eliminates them; (2) bracket seeding is visible before the start tx lands, so the
///         trigger holder can front-run the seeding to get favorable placement.
/// @dev Demonstrates: tournament integrity as a timing-as-attack-surface problem.
contract TournamentBracket is AutoLoopVRFCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    enum Phase {
        Registration,
        Active,
        Complete
    }

    struct MatchResult {
        address winner;
        address loser;
        uint256 round;
        uint256 matchIndex;
        bytes32 seed;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    Phase public phase;
    uint8 public maxPlayers;
    uint256 public roundInterval;
    uint256 public lastRoundTime;

    address[] public players;
    mapping(address => bool) public registered;

    // Active bracket: slot index → player (address(0) = eliminated)
    mapping(uint256 => address) public bracket;
    uint256 public activePlayers;

    uint256 public currentRound;
    address public champion;

    uint256 public prizePool;
    uint256 public protocolFeeBalance;
    uint256 public constant PROTOCOL_FEE_BPS = 300; // 3%

    uint256 public entryFee;

    MatchResult[] public matchHistory;

    // ── Events ─────────────────────────────────────────────────────────────────

    event PlayerRegistered(address indexed player, uint256 slot);
    event TournamentStarted(uint256 playerCount, uint256 prizePool);
    event RoundComplete(uint256 indexed round, uint256 matchesPlayed, uint256 remainingPlayers);
    event MatchPlayed(
        address indexed winner,
        address indexed loser,
        uint256 round,
        uint256 matchIndex,
        bytes32 seed
    );
    event ChampionCrowned(address indexed champion, uint256 prize);
    event Refunded(address indexed player, uint256 amount);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _roundInterval Minimum seconds between rounds
    /// @param _maxPlayers    Must be a power of 2 (4, 8, or 16)
    /// @param _entryFee      Wei required to register
    constructor(uint256 _roundInterval, uint8 _maxPlayers, uint256 _entryFee) {
        require(_roundInterval > 0, "TournamentBracket: interval=0");
        require(
            _maxPlayers == 4 || _maxPlayers == 8 || _maxPlayers == 16,
            "TournamentBracket: maxPlayers must be 4, 8, or 16"
        );
        roundInterval = _roundInterval;
        maxPlayers = _maxPlayers;
        entryFee = _entryFee;
        phase = Phase.Registration;
    }

    // ── Registration ──────────────────────────────────────────────────────────

    function register() external payable {
        require(phase == Phase.Registration, "TournamentBracket: not registration");
        require(!registered[msg.sender], "TournamentBracket: already registered");
        require(players.length < maxPlayers, "TournamentBracket: full");
        require(msg.value >= entryFee, "TournamentBracket: insufficient entry fee");

        registered[msg.sender] = true;
        players.push(msg.sender);
        prizePool += entryFee;

        // Refund overpayment
        uint256 excess = msg.value - entryFee;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "TournamentBracket: refund failed");
        }

        emit PlayerRegistered(msg.sender, players.length - 1);
    }

    // ── Admin — start tournament ───────────────────────────────────────────────

    /// @notice Start the tournament. Bracket assignment happens in the first progressLoop tick.
    function startTournament() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(phase == Phase.Registration, "TournamentBracket: already started");
        require(players.length == maxPlayers, "TournamentBracket: not full");
        phase = Phase.Active;
        activePlayers = maxPlayers;
        lastRoundTime = block.timestamp;
        emit TournamentStarted(players.length, prizePool);
    }

    /// @notice Refund entry fees if admin never starts the tournament.
    function withdrawIfNoStart() external {
        require(phase == Phase.Registration, "TournamentBracket: tournament started");
        require(registered[msg.sender], "TournamentBracket: not registered");
        registered[msg.sender] = false;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) {
                players[i] = players[players.length - 1];
                players.pop();
                break;
            }
        }
        prizePool -= entryFee;
        (bool ok,) = msg.sender.call{value: entryFee}("");
        require(ok, "TournamentBracket: refund failed");
        emit Refunded(msg.sender, entryFee);
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        // First tick (round 0, bracket not yet seeded): seed the bracket
        // Subsequent ticks: resolve the current round
        bool needsSeed = (phase == Phase.Active && currentRound == 0 && bracket[0] == address(0));
        bool roundReady = phase == Phase.Active
            && (block.timestamp - lastRoundTime) >= roundInterval && activePlayers > 1;

        loopIsReady = needsSeed || roundReady;
        progressWithData = abi.encode(_loopID, activePlayers);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness,) = _verifyAndExtractRandomness(progressWithData, msg.sender);

        require(phase == Phase.Active, "TournamentBracket: not active");

        bool needsSeed = (currentRound == 0 && bracket[0] == address(0));

        if (needsSeed) {
            _seedBracket(randomness);
            lastRoundTime = block.timestamp;
            ++_loopID;
            return;
        }

        require((block.timestamp - lastRoundTime) >= roundInterval, "TournamentBracket: too soon");
        require(activePlayers > 1, "TournamentBracket: only one player");

        lastRoundTime = block.timestamp;
        ++_loopID;

        _resolveRound(randomness);
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    /// @dev Shuffle players array into bracket slots using VRF.
    function _seedBracket(bytes32 randomness) internal {
        uint256 n = players.length;
        address[] memory shuffled = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            shuffled[i] = players[i];
        }

        for (uint256 i = n - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encodePacked(randomness, i))) % (i + 1);
            address tmp = shuffled[i];
            shuffled[i] = shuffled[j];
            shuffled[j] = tmp;
        }

        for (uint256 i = 0; i < n; i++) {
            bracket[i] = shuffled[i];
        }
    }

    /// @dev Resolve all matches in the current round. Winners stay, losers are eliminated.
    function _resolveRound(bytes32 randomness) internal {
        uint256 matchesThisRound = activePlayers / 2;
        uint256 matchIdx = 0;

        // Collect active slots
        uint256[] memory activeSlots = new uint256[](activePlayers);
        uint256 count;
        for (uint256 i = 0; i < maxPlayers; i++) {
            if (bracket[i] != address(0)) {
                activeSlots[count++] = i;
            }
        }

        for (uint256 m = 0; m < matchesThisRound; m++) {
            uint256 slotA = activeSlots[m * 2];
            uint256 slotB = activeSlots[m * 2 + 1];
            address p1 = bracket[slotA];
            address p2 = bracket[slotB];

            bytes32 matchSeed = keccak256(abi.encodePacked(randomness, currentRound, m));
            bool p1wins = (uint256(matchSeed) % 2 == 0);

            address winner = p1wins ? p1 : p2;
            address loser = p1wins ? p2 : p1;

            // Eliminate loser — keep winner in lower slot, clear higher slot
            bracket[slotA] = winner;
            bracket[slotB] = address(0);

            matchHistory.push(
                MatchResult({
                    winner: winner,
                    loser: loser,
                    round: currentRound,
                    matchIndex: matchIdx++,
                    seed: matchSeed
                })
            );

            emit MatchPlayed(winner, loser, currentRound, matchIdx - 1, matchSeed);
        }

        currentRound++;
        activePlayers -= matchesThisRound;

        emit RoundComplete(currentRound - 1, matchesThisRound, activePlayers);

        if (activePlayers == 1) {
            _crownChampion();
        }
    }

    function _crownChampion() internal {
        // Find the remaining player
        for (uint256 i = 0; i < maxPlayers; i++) {
            if (bracket[i] != address(0)) {
                champion = bracket[i];
                break;
            }
        }
        phase = Phase.Complete;

        uint256 fee = (prizePool * PROTOCOL_FEE_BPS) / 10_000;
        uint256 prize = prizePool - fee;
        protocolFeeBalance += fee;
        prizePool = 0;

        (bool ok,) = champion.call{value: prize}("");
        require(ok, "TournamentBracket: prize transfer failed");

        emit ChampionCrowned(champion, prize);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "TournamentBracket: fee withdraw failed");
    }

    function setRoundInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "TournamentBracket: interval=0");
        roundInterval = _interval;
    }

    // ── Views ──────────────────────────────────────────────────────────────────

    function playerCount() external view returns (uint256) {
        return players.length;
    }

    function matchHistoryLength() external view returns (uint256) {
        return matchHistory.length;
    }

    receive() external payable {}
}
