// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopCompatible.sol";

/// @title NFTRegistry
/// @notice Enforces a scheduled NFT release calendar on-chain. "Limited" supply is a
///         promise without AutoLoop — any operator can delay or skip a release. The
///         AutoLoop tick fires regardless of operator intent, executing the scheduled
///         mint at the committed time.
/// @dev Demonstrates: supply scarcity as an enforcement problem, not just a policy problem.
contract NFTRegistry is AutoLoopCompatible {
    // ── Types ──────────────────────────────────────────────────────────────────

    struct Collection {
        string name;
        uint256 maxSupply;
        uint256 minted;
        uint256 mintPrice;
        bool releaseComplete;
    }

    struct ReleaseSlot {
        uint256 collectionId;
        uint256 quantity;
        uint256 releaseTime;
        bool executed;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    mapping(uint256 => Collection) public collections;
    uint256 public nextCollectionId;

    ReleaseSlot[] public releaseSchedule;

    mapping(uint256 => address) public ownerOf; // tokenId → holder (address(0) = treasury)
    mapping(uint256 => uint256) public tokenCollection; // tokenId → collectionId
    mapping(uint256 => bool) public claimed;

    uint256 public nextTokenId;

    uint256 public constant PROTOCOL_FEE_BPS = 200; // 2%
    uint256 public protocolFeeBalance;
    address public treasury;

    // ── Events ─────────────────────────────────────────────────────────────────

    event CollectionCreated(
        uint256 indexed collectionId, string name, uint256 maxSupply, uint256 mintPrice
    );
    event ReleaseScheduled(
        uint256 indexed slotIndex,
        uint256 indexed collectionId,
        uint256 quantity,
        uint256 releaseTime
    );
    event SupplyReleased(
        uint256 indexed collectionId, uint256 quantity, uint256 totalMinted, uint256 scheduledTime
    );
    event TokenClaimed(uint256 indexed tokenId, address indexed claimer, uint256 collectionId);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _treasury Address that receives minted-but-unclaimed tokens
    constructor(address _treasury) {
        require(_treasury != address(0), "NFTRegistry: zero treasury");
        treasury = _treasury;
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    /// @notice Ready when at least one release slot has passed its release time.
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        uint256 readySlot = _firstDueSlot();
        loopIsReady = readySlot != type(uint256).max;
        progressWithData = abi.encode(_loopID, readySlot);
    }

    /// @notice Execute the first due release slot — mint tokens to treasury.
    function progressLoop(bytes calldata progressWithData) external override {
        (uint256 loopID, uint256 slotIdx) = abi.decode(progressWithData, (uint256, uint256));
        require(loopID == _loopID, "NFTRegistry: stale loop id");

        ReleaseSlot storage slot = releaseSchedule[slotIdx];
        require(!slot.executed, "NFTRegistry: already executed");
        require(block.timestamp >= slot.releaseTime, "NFTRegistry: too early");

        Collection storage col = collections[slot.collectionId];
        require(col.minted + slot.quantity <= col.maxSupply, "NFTRegistry: exceeds max supply");

        ++_loopID;
        slot.executed = true;

        uint256 startToken = nextTokenId;
        for (uint256 i = 0; i < slot.quantity; i++) {
            uint256 tokenId = nextTokenId++;
            ownerOf[tokenId] = treasury;
            tokenCollection[tokenId] = slot.collectionId;
        }
        col.minted += slot.quantity;

        emit SupplyReleased(slot.collectionId, slot.quantity, col.minted, slot.releaseTime);
        (startToken); // suppress unused warning
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    /// @notice Register a new collection.
    function createCollection(string calldata name, uint256 maxSupply, uint256 mintPrice)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 collectionId)
    {
        require(maxSupply > 0, "NFTRegistry: zero maxSupply");
        collectionId = nextCollectionId++;
        collections[collectionId] = Collection({
            name: name,
            maxSupply: maxSupply,
            minted: 0,
            mintPrice: mintPrice,
            releaseComplete: false
        });
        emit CollectionCreated(collectionId, name, maxSupply, mintPrice);
    }

    /// @notice Schedule a future release of `quantity` tokens from a collection.
    function scheduleRelease(uint256 collectionId, uint256 quantity, uint256 releaseTime)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 slotIndex)
    {
        require(collectionId < nextCollectionId, "NFTRegistry: unknown collection");
        require(quantity > 0, "NFTRegistry: zero quantity");
        require(releaseTime > block.timestamp, "NFTRegistry: release in past");

        // Validate total scheduled ≤ maxSupply
        uint256 totalScheduled = collections[collectionId].minted;
        for (uint256 i = 0; i < releaseSchedule.length; i++) {
            ReleaseSlot storage s = releaseSchedule[i];
            if (s.collectionId == collectionId && !s.executed) {
                totalScheduled += s.quantity;
            }
        }
        require(
            totalScheduled + quantity <= collections[collectionId].maxSupply,
            "NFTRegistry: would exceed max supply"
        );

        slotIndex = releaseSchedule.length;
        releaseSchedule.push(
            ReleaseSlot({
                collectionId: collectionId,
                quantity: quantity,
                releaseTime: releaseTime,
                executed: false
            })
        );
        emit ReleaseScheduled(slotIndex, collectionId, quantity, releaseTime);
    }

    /// @notice Update treasury address.
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "NFTRegistry: zero treasury");
        treasury = _treasury;
    }

    /// @notice Withdraw accumulated protocol fees.
    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "NFTRegistry: fee withdraw failed");
    }

    // ── User actions ───────────────────────────────────────────────────────────

    /// @notice Claim a token from treasury by paying mintPrice.
    function claim(uint256 tokenId) external payable {
        require(ownerOf[tokenId] == treasury, "NFTRegistry: not claimable");
        require(!claimed[tokenId], "NFTRegistry: already claimed");

        uint256 colId = tokenCollection[tokenId];
        uint256 price = collections[colId].mintPrice;
        require(msg.value >= price, "NFTRegistry: insufficient payment");

        claimed[tokenId] = true;
        ownerOf[tokenId] = msg.sender;

        uint256 fee = (price * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;

        // Refund overpayment
        uint256 excess = msg.value - price;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "NFTRegistry: refund failed");
        }

        emit TokenClaimed(tokenId, msg.sender, colId);
    }

    // ── Views ──────────────────────────────────────────────────────────────────

    function getReleaseScheduleLength() external view returns (uint256) {
        return releaseSchedule.length;
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    function _firstDueSlot() internal view returns (uint256) {
        for (uint256 i = 0; i < releaseSchedule.length; i++) {
            ReleaseSlot storage s = releaseSchedule[i];
            if (!s.executed && block.timestamp >= s.releaseTime) {
                return i;
            }
        }
        return type(uint256).max;
    }
}
