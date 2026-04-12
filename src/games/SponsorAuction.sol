// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title SponsorAuction (Rolling Auction)
 * @author LuckyMachines LLC
 * @notice A perpetual ascending-bid auction for a single sponsorship slot.
 *         Auctions run back-to-back: when one closes on schedule, the next
 *         opens in the same transaction. The slot winner is entitled to
 *         display sponsorship on the tied NFT asset for `sponsorshipPeriod`
 *         seconds.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Timing-as-attack-surface. The auction close is a discrete event with
 *      strictly conflicting incentives:
 *
 *        - The current high bidder wants it closed *immediately* so no
 *          counter-bid can arrive.
 *        - Anyone considering a counter-bid wants it kept open as long as
 *          possible to get more time.
 *        - The slot receiver (Lucky Machines or a delegated NFT owner) wants
 *          it closed at the moment the highest bid is in.
 *
 *      No player-controlled trigger can be fair. A neutral scheduler running
 *      on a fixed block cadence is the only way to guarantee the close
 *      happens at the same moment for everyone. This is the cleanest
 *      "no randomness but still needs autoloop" demo in the stack — the
 *      proof that AutoLoop's value extends beyond VRF.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - protocolRakeBps on each winning bid → protocolFeeBalance
 *      - remainder paid to slotReceiver       → non-custodial
 *      - minimum bid increment prevents spam
 */
contract SponsorAuction is AutoLoopCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event AuctionOpened(
        uint256 indexed auctionId,
        uint256 startedAt,
        uint256 closesAt
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    event AuctionClosed(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid,
        uint256 slotReceiverPayout,
        uint256 protocolFee
    );
    event AuctionClosedNoBids(uint256 indexed auctionId);
    event SponsorshipExpired(uint256 indexed auctionId);
    event SlotReceiverUpdated(
        address indexed oldReceiver,
        address indexed newReceiver
    );
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable + admin)
    // ===============================================================

    uint256 public immutable auctionDuration;
    uint256 public immutable sponsorshipPeriod;
    uint256 public immutable minBid;
    uint256 public immutable minIncrementBps;
    uint256 public immutable protocolRakeBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public slotReceiver;

    // ===============================================================
    //  State
    // ===============================================================

    uint256 public currentAuctionId;
    uint256 public auctionStartedAt;
    uint256 public auctionClosesAt;
    address public highestBidder;
    uint256 public highestBid;
    bool public auctionOpen;

    address public currentSponsor;
    uint256 public sponsorshipExpiresAt;

    uint256 public protocolFeeBalance;
    uint256 public totalAuctionsClosed;
    uint256 public totalBidsPlaced;

    mapping(address => uint256) public refunds;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _auctionDuration,
        uint256 _sponsorshipPeriod,
        uint256 _minBid,
        uint256 _minIncrementBps,
        uint256 _protocolRakeBps,
        address _slotReceiver
    ) {
        require(_auctionDuration > 0, "SponsorAuction: duration=0");
        require(_sponsorshipPeriod > 0, "SponsorAuction: period=0");
        require(_minBid > 0, "SponsorAuction: minBid=0");
        require(_minIncrementBps > 0, "SponsorAuction: increment=0");
        require(_protocolRakeBps <= 2000, "SponsorAuction: rake > 20%");
        require(_slotReceiver != address(0), "SponsorAuction: receiver=0");

        auctionDuration = _auctionDuration;
        sponsorshipPeriod = _sponsorshipPeriod;
        minBid = _minBid;
        minIncrementBps = _minIncrementBps;
        protocolRakeBps = _protocolRakeBps;
        slotReceiver = _slotReceiver;

        _openAuction();
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    function bid() external payable {
        require(auctionOpen, "SponsorAuction: auction closed");
        require(
            block.timestamp < auctionClosesAt,
            "SponsorAuction: auction expired"
        );

        uint256 requiredBid;
        if (highestBid == 0) {
            requiredBid = minBid;
        } else {
            uint256 increment = (highestBid * minIncrementBps) /
                BPS_DENOMINATOR;
            if (increment == 0) increment = 1;
            requiredBid = highestBid + increment;
        }
        require(msg.value >= requiredBid, "SponsorAuction: bid too low");

        // Refund the previous highest bidder via pull-payment
        if (highestBidder != address(0)) {
            refunds[highestBidder] += highestBid;
        }

        highestBid = msg.value;
        highestBidder = _msgSender();
        totalBidsPlaced++;

        emit BidPlaced(currentAuctionId, _msgSender(), msg.value);
    }

    function claimRefund() external {
        uint256 amount = refunds[_msgSender()];
        require(amount > 0, "SponsorAuction: no refund");
        refunds[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "SponsorAuction: refund failed");
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
        loopIsReady =
            auctionOpen &&
            block.timestamp >= auctionClosesAt;
        progressWithData = abi.encode(currentAuctionId);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        uint256 expectedAuctionId = abi.decode(progressWithData, (uint256));
        require(auctionOpen, "SponsorAuction: not open");
        require(
            block.timestamp >= auctionClosesAt,
            "SponsorAuction: too soon"
        );
        require(
            expectedAuctionId == currentAuctionId,
            "SponsorAuction: stale id"
        );

        auctionOpen = false;

        if (highestBidder == address(0)) {
            emit AuctionClosedNoBids(currentAuctionId);
        } else {
            uint256 winningBid = highestBid;
            uint256 protocolCut = (winningBid * protocolRakeBps) /
                BPS_DENOMINATOR;
            uint256 payout = winningBid - protocolCut;
            protocolFeeBalance += protocolCut;

            // Credit slotReceiver via pull-payment so failures don't
            // block the loop
            refunds[slotReceiver] += payout;

            currentSponsor = highestBidder;
            sponsorshipExpiresAt = block.timestamp + sponsorshipPeriod;

            emit AuctionClosed(
                currentAuctionId,
                highestBidder,
                winningBid,
                payout,
                protocolCut
            );
        }

        totalAuctionsClosed++;
        _openAuction();
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function currentMinBid() external view returns (uint256) {
        if (highestBid == 0) return minBid;
        uint256 increment = (highestBid * minIncrementBps) / BPS_DENOMINATOR;
        if (increment == 0) increment = 1;
        return highestBid + increment;
    }

    function sponsorshipActive() external view returns (bool) {
        return
            currentSponsor != address(0) &&
            block.timestamp < sponsorshipExpiresAt;
    }

    // ===============================================================
    //  Admin
    // ===============================================================

    function setSlotReceiver(
        address newReceiver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newReceiver != address(0), "SponsorAuction: receiver=0");
        emit SlotReceiverUpdated(slotReceiver, newReceiver);
        slotReceiver = newReceiver;
    }

    function withdrawProtocolFees(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "SponsorAuction: zero address");
        require(
            amount <= protocolFeeBalance,
            "SponsorAuction: exceeds balance"
        );
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "SponsorAuction: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    // ===============================================================
    //  Internal
    // ===============================================================

    function _openAuction() internal {
        currentAuctionId++;
        auctionStartedAt = block.timestamp;
        auctionClosesAt = block.timestamp + auctionDuration;
        highestBidder = address(0);
        highestBid = 0;
        auctionOpen = true;
        emit AuctionOpened(currentAuctionId, auctionStartedAt, auctionClosesAt);
    }

    receive() external payable {}
}
