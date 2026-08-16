// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopVRFCompatible.sol";

/// @title MatchmakingEngine
/// @notice Pairs players from an open registration pool on an autonomous schedule using VRF.
///         The core reason self-triggering fails: whoever holds the trigger sees the VRF output
///         before submitting the transaction. They can cherry-pick the moment — withhold if
///         paired unfavorably, submit if paired favorably. Neutral keeper removes this.
/// @dev Demonstrates: matchmaking as a front-running attack surface.
contract MatchmakingEngine is AutoLoopVRFCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct Match {
        uint256 matchId;
        address player1;
        address player2;
        bytes32 seed;
        uint256 timestamp;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    address[] public pool;
    mapping(address => bool) public registered;

    uint256 public matchInterval;
    uint256 public lastMatch;
    uint256 public matchCount;

    mapping(uint256 => Match) public matches;

    // ── Events ─────────────────────────────────────────────────────────────────

    event PlayerRegistered(address indexed player);
    event PlayerDeregistered(address indexed player);
    event MatchMade(address indexed player1, address indexed player2, uint256 indexed matchId, bytes32 seed);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _matchInterval Minimum seconds between match rounds
    constructor(uint256 _matchInterval) {
        require(_matchInterval > 0, "MatchmakingEngine: interval=0");
        matchInterval = _matchInterval;
        lastMatch = block.timestamp;
    }

    // ── Player actions ─────────────────────────────────────────────────────────

    function register() external {
        require(!registered[msg.sender], "MatchmakingEngine: already registered");
        registered[msg.sender] = true;
        pool.push(msg.sender);
        emit PlayerRegistered(msg.sender);
    }

    function deregister() external {
        require(registered[msg.sender], "MatchmakingEngine: not registered");
        registered[msg.sender] = false;
        // Swap-and-pop to remove from pool
        for (uint256 i = 0; i < pool.length; i++) {
            if (pool[i] == msg.sender) {
                pool[i] = pool[pool.length - 1];
                pool.pop();
                break;
            }
        }
        emit PlayerDeregistered(msg.sender);
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = pool.length >= 2
            && (block.timestamp - lastMatch) >= matchInterval;
        progressWithData = abi.encode(_loopID, pool.length);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness,) = _verifyAndExtractRandomness(progressWithData, msg.sender);

        require(pool.length >= 2, "MatchmakingEngine: not enough players");
        require((block.timestamp - lastMatch) >= matchInterval, "MatchmakingEngine: too soon");

        lastMatch = block.timestamp;
        ++_loopID;

        _runMatches(randomness);
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    /// @dev Fisher-Yates shuffle of pool using VRF seed, then pair adjacent players.
    function _runMatches(bytes32 randomness) internal {
        // Copy pool to memory for shuffling
        uint256 n = pool.length;
        address[] memory shuffled = new address[](n);
        for (uint256 i = 0; i < n; i++) shuffled[i] = pool[i];

        // Fisher-Yates in-place shuffle
        for (uint256 i = n - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encodePacked(randomness, i))) % (i + 1);
            address tmp = shuffled[i];
            shuffled[i] = shuffled[j];
            shuffled[j] = tmp;
        }

        // Pair consecutive players
        for (uint256 i = 0; i + 1 < n; i += 2) {
            bytes32 seed = keccak256(abi.encodePacked(randomness, matchCount));
            uint256 matchId = matchCount++;
            matches[matchId] = Match({
                matchId:   matchId,
                player1:   shuffled[i],
                player2:   shuffled[i + 1],
                seed:      seed,
                timestamp: block.timestamp
            });
            emit MatchMade(shuffled[i], shuffled[i + 1], matchId, seed);
        }
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setMatchInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "MatchmakingEngine: interval=0");
        matchInterval = _interval;
    }

    // ── Views ──────────────────────────────────────────────────────────────────

    function poolSize() external view returns (uint256) {
        return pool.length;
    }
}
