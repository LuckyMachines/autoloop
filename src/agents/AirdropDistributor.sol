// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopVRFCompatible.sol";

/// @title AirdropDistributor
/// @notice Draws N winners from a registered address pool using VRF on an autonomous schedule.
///         If player-controlled, the trigger holder computes who wins before submitting and only
///         calls when favorable. VRF + neutral scheduling removes both front-running and bias.
/// @dev Demonstrates: selection events with real value attached cannot be safely self-triggered.
contract AirdropDistributor is AutoLoopVRFCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct Round {
        uint256 id;
        uint256 prizePerWinner;
        uint256 winnersCount;
        address[] winners;
        bool     settled;
        uint256  timestamp;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    address[] public pool;
    mapping(address => bool) public registered;

    uint256 public drawInterval;
    uint256 public lastDraw;
    uint256 public winnersPerDraw;
    uint256 public prizePerWinner;   // fixed ETH prize per winner
    uint256 public roundCount;
    uint256 public protocolFeeBalance;

    uint256 public constant PROTOCOL_FEE_BPS = 200; // 2%
    uint256 public constant MAX_POOL_SIZE = 10_000;

    mapping(uint256 => Round) public rounds;

    // ── Events ─────────────────────────────────────────────────────────────────

    event Registered(address indexed participant);
    event Deregistered(address indexed participant);
    event DrawSettled(uint256 indexed roundId, address[] winners, uint256 prizeEach, uint256 loopID);

    // ── Construction ───────────────────────────────────────────────────────────

    constructor(uint256 _drawInterval, uint256 _winnersPerDraw, uint256 _prizePerWinner) {
        require(_drawInterval > 0, "AirdropDistributor: interval=0");
        require(_winnersPerDraw > 0, "AirdropDistributor: winners=0");
        drawInterval = _drawInterval;
        winnersPerDraw = _winnersPerDraw;
        prizePerWinner = _prizePerWinner;
        lastDraw = block.timestamp;
    }

    // ── Registration ──────────────────────────────────────────────────────────

    function register() external {
        require(!registered[msg.sender], "AirdropDistributor: already registered");
        require(pool.length < MAX_POOL_SIZE, "AirdropDistributor: pool full");
        registered[msg.sender] = true;
        pool.push(msg.sender);
        emit Registered(msg.sender);
    }

    function deregister() external {
        require(registered[msg.sender], "AirdropDistributor: not registered");
        registered[msg.sender] = false;
        // Swap-and-pop
        for (uint256 i = 0; i < pool.length; i++) {
            if (pool[i] == msg.sender) {
                pool[i] = pool[pool.length - 1];
                pool.pop();
                break;
            }
        }
        emit Deregistered(msg.sender);
    }

    function poolSize() external view returns (uint256) { return pool.length; }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        bool ready = pool.length >= winnersPerDraw
            && (block.timestamp - lastDraw) >= drawInterval
            && address(this).balance >= prizePerWinner * winnersPerDraw;
        loopIsReady = ready;
        progressWithData = abi.encode(_loopID);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness,) = _verifyAndExtractRandomness(progressWithData, msg.sender);
        uint256 loopID = abi.decode(abi.encode(_loopID), (uint256));
        // Re-read _loopID before increment (verifyAndExtract doesn't change it)
        uint256 currentLoopID = _loopID;

        require(pool.length >= winnersPerDraw, "AirdropDistributor: pool too small");
        require((block.timestamp - lastDraw) >= drawInterval, "AirdropDistributor: too soon");
        require(address(this).balance >= prizePerWinner * winnersPerDraw, "AirdropDistributor: insufficient funds");

        lastDraw = block.timestamp;
        ++_loopID;

        // VRF-seeded winner selection (Fisher-Yates partial shuffle)
        uint256 n = pool.length;
        address[] memory poolCopy = new address[](n);
        for (uint256 i = 0; i < n; i++) poolCopy[i] = pool[i];

        address[] memory winners = new address[](winnersPerDraw);
        for (uint256 i = 0; i < winnersPerDraw; i++) {
            uint256 remaining = n - i;
            uint256 idx = i + uint256(keccak256(abi.encodePacked(randomness, i))) % remaining;
            winners[i] = poolCopy[idx];
            poolCopy[idx] = poolCopy[i];
        }

        // Record round
        uint256 roundId = roundCount++;
        rounds[roundId].id = roundId;
        rounds[roundId].prizePerWinner = prizePerWinner;
        rounds[roundId].winnersCount = winnersPerDraw;
        rounds[roundId].settled = true;
        rounds[roundId].timestamp = block.timestamp;
        for (uint256 i = 0; i < winners.length; i++) rounds[roundId].winners.push(winners[i]);

        // Distribute prizes
        uint256 totalPrize = prizePerWinner * winnersPerDraw;
        uint256 fee = (totalPrize * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;

        uint256 payoutEach = (totalPrize - fee) / winnersPerDraw;
        for (uint256 i = 0; i < winners.length; i++) {
            (bool ok,) = winners[i].call{value: payoutEach}("");
            require(ok, "AirdropDistributor: payout failed");
        }

        emit DrawSettled(roundId, winners, payoutEach, currentLoopID);
        (randomness); // suppress unused warning
        (loopID);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setDrawInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "AirdropDistributor: interval=0");
        drawInterval = _interval;
    }

    function setWinnersPerDraw(uint256 _n) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_n > 0, "AirdropDistributor: winners=0");
        winnersPerDraw = _n;
    }

    function setPrizePerWinner(uint256 _prize) external onlyRole(DEFAULT_ADMIN_ROLE) {
        prizePerWinner = _prize;
    }

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "AirdropDistributor: fee withdraw failed");
    }

    receive() external payable {}
}
