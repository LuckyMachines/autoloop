// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopVRFCompatible.sol";

/// @title LotterySweepstakes
/// @notice A recurring draw where depositors enter a prize pool and VRF selects one winner
///         per round on an autonomous schedule. Rounds run back-to-back automatically.
///         Identical inverted-interest structure to CrumbleCore: every depositor wants
///         someone else to trigger the draw (they might win nothing), but nobody will.
///         A neutral keeper is the only way the lottery runs.
/// @dev Demonstrates: financial lotteries face the same structural self-trigger failure as
///      attrition games.
contract LotterySweepstakes is AutoLoopVRFCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct Round {
        uint256 id;
        address winner;
        uint256 prize;
        uint256 entrantCount;
        uint256 timestamp;
        uint256 loopID;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    uint256 public ticketPrice;
    uint256 public roundInterval;    // minimum seconds between draws
    uint256 public lastDraw;
    uint256 public roundCount;

    address[] public currentEntrants;
    mapping(address => uint256) public ticketCount;

    uint256 public protocolFeeBalance;
    uint256 public constant PROTOCOL_FEE_BPS = 300; // 3%

    mapping(uint256 => Round) public rounds;

    // ── Events ─────────────────────────────────────────────────────────────────

    event TicketPurchased(address indexed buyer, uint256 tickets, uint256 roundId);
    event RoundSettled(uint256 indexed roundId, address winner, uint256 prize, uint256 loopID);

    // ── Construction ───────────────────────────────────────────────────────────

    constructor(uint256 _ticketPrice, uint256 _roundInterval) {
        require(_ticketPrice > 0, "LotterySweepstakes: ticketPrice=0");
        require(_roundInterval > 0, "LotterySweepstakes: interval=0");
        ticketPrice = _ticketPrice;
        roundInterval = _roundInterval;
        lastDraw = block.timestamp;
    }

    // ── Player actions ─────────────────────────────────────────────────────────

    function buyTickets(uint256 count) external payable {
        require(count > 0, "LotterySweepstakes: count=0");
        require(msg.value == ticketPrice * count, "LotterySweepstakes: wrong value");

        if (ticketCount[msg.sender] == 0) {
            currentEntrants.push(msg.sender);
        }
        ticketCount[msg.sender] += count;
        emit TicketPurchased(msg.sender, count, roundCount);
    }

    function entrantCount() external view returns (uint256) { return currentEntrants.length; }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = currentEntrants.length > 0
            && (block.timestamp - lastDraw) >= roundInterval;
        progressWithData = abi.encode(_loopID, currentEntrants.length);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness,) = _verifyAndExtractRandomness(progressWithData, msg.sender);
        uint256 currentLoopID = _loopID;

        require(currentEntrants.length > 0, "LotterySweepstakes: no entrants");
        require((block.timestamp - lastDraw) >= roundInterval, "LotterySweepstakes: too soon");

        lastDraw = block.timestamp;
        ++_loopID;

        // Build weighted ticket array and pick winner
        uint256 totalTickets;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalTickets += ticketCount[currentEntrants[i]];
        }

        uint256 winnerIdx = uint256(randomness) % totalTickets;
        uint256 cumulative;
        address winner;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += ticketCount[currentEntrants[i]];
            if (winnerIdx < cumulative) {
                winner = currentEntrants[i];
                break;
            }
        }

        // Calculate prize
        uint256 pool = address(this).balance - protocolFeeBalance;
        uint256 fee = (pool * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;
        uint256 prize = pool - fee;

        // Record round
        uint256 roundId = roundCount++;
        rounds[roundId] = Round({
            id: roundId,
            winner: winner,
            prize: prize,
            entrantCount: currentEntrants.length,
            timestamp: block.timestamp,
            loopID: currentLoopID
        });

        // Reset for next round
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            ticketCount[currentEntrants[i]] = 0;
        }
        delete currentEntrants;

        // Pay winner
        (bool ok,) = winner.call{value: prize}("");
        require(ok, "LotterySweepstakes: prize transfer failed");

        emit RoundSettled(roundId, winner, prize, currentLoopID);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setTicketPrice(uint256 _price) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_price > 0, "LotterySweepstakes: ticketPrice=0");
        ticketPrice = _price;
    }

    function setRoundInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval > 0, "LotterySweepstakes: interval=0");
        roundInterval = _interval;
    }

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "LotterySweepstakes: fee withdraw failed");
    }

    receive() external payable {}
}
