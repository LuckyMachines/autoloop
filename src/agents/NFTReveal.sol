// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopVRFCompatible.sol";

/// @title NFTReveal
/// @notice Autonomously reveals NFT traits after a mint closes. VRF seeds trait
///         assignment for all unrevealed tokens in one transaction, on a pre-committed
///         schedule. If player-triggered, the triggerer computes all traits before calling
///         and only proceeds when holding rare tokens. VRF + AutoLoop makes that impossible.
/// @dev Demonstrates: NFT reveal timing is an attack surface when any token holder controls it.
contract NFTReveal is AutoLoopVRFCompatible {
    // ── State ──────────────────────────────────────────────────────────────────

    uint256 public nextTokenId;
    uint256 public maxSupply;
    uint256 public mintPrice;
    bool    public mintOpen;
    bool    public revealed;

    /// @notice Configurable trait tiers (must sum to 10000 bps).
    uint256[] public rarityTiersBps;   // e.g. [5000, 3000, 1500, 500] = Common/Uncommon/Rare/Legendary
    string[]  public rarityTierNames;

    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint256) public tokenTier; // 0 = unrevealed

    uint256 public revealTime;    // earliest timestamp for reveal
    bytes32 public revealSeed;    // set by VRF on reveal
    uint256 public protocolFeeBalance;

    uint256 public constant PROTOCOL_FEE_BPS = 500; // 5% of mint proceeds

    // ── Events ─────────────────────────────────────────────────────────────────

    event Minted(address indexed to, uint256 indexed tokenId);
    event Revealed(bytes32 seed, uint256 totalTokens, uint256 loopID);
    event TraitAssigned(uint256 indexed tokenId, uint256 tier, string tierName);
    event MintOpened();
    event MintClosed();

    // ── Construction ───────────────────────────────────────────────────────────

    constructor(
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _revealTime,
        uint256[] memory _rarityTiersBps,
        string[] memory _rarityTierNames
    ) {
        require(_maxSupply > 0, "NFTReveal: maxSupply=0");
        require(_revealTime > block.timestamp, "NFTReveal: reveal in past");
        require(_rarityTiersBps.length == _rarityTierNames.length, "NFTReveal: tier length mismatch");
        uint256 total;
        for (uint256 i = 0; i < _rarityTiersBps.length; i++) total += _rarityTiersBps[i];
        require(total == 10_000, "NFTReveal: tiers must sum to 10000");

        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        revealTime = _revealTime;
        rarityTiersBps = _rarityTiersBps;
        rarityTierNames = _rarityTierNames;
    }

    // ── Mint ──────────────────────────────────────────────────────────────────

    function openMint() external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintOpen = true;
        emit MintOpened();
    }

    function closeMint() external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintOpen = false;
        emit MintClosed();
    }

    function mint() external payable {
        require(mintOpen, "NFTReveal: mint closed");
        require(!revealed, "NFTReveal: already revealed");
        require(nextTokenId < maxSupply, "NFTReveal: sold out");
        require(msg.value >= mintPrice, "NFTReveal: insufficient payment");

        uint256 tokenId = ++nextTokenId;
        ownerOf[tokenId] = msg.sender;

        uint256 fee = (msg.value * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;

        emit Minted(msg.sender, tokenId);
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = !revealed
            && nextTokenId > 0
            && block.timestamp >= revealTime;
        progressWithData = abi.encode(_loopID, nextTokenId);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness,) = _verifyAndExtractRandomness(progressWithData, msg.sender);
        uint256 currentLoopID = _loopID;

        require(!revealed, "NFTReveal: already revealed");
        require(nextTokenId > 0, "NFTReveal: no tokens minted");
        require(block.timestamp >= revealTime, "NFTReveal: too soon");

        revealed = true;
        revealSeed = randomness;
        ++_loopID;

        // Assign traits to all minted tokens using VRF seed
        for (uint256 i = 1; i <= nextTokenId; i++) {
            uint256 roll = uint256(keccak256(abi.encodePacked(randomness, i))) % 10_000;
            uint256 cumulative = 0;
            for (uint256 t = 0; t < rarityTiersBps.length; t++) {
                cumulative += rarityTiersBps[t];
                if (roll < cumulative) {
                    tokenTier[i] = t + 1; // 1-indexed; 0 = unrevealed
                    emit TraitAssigned(i, t + 1, rarityTierNames[t]);
                    break;
                }
            }
        }

        emit Revealed(randomness, nextTokenId, currentLoopID);
    }

    // ── View ──────────────────────────────────────────────────────────────────

    function tierName(uint256 tokenId) external view returns (string memory) {
        uint256 tier = tokenTier[tokenId];
        if (tier == 0) return "Unrevealed";
        return rarityTierNames[tier - 1];
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setRevealTime(uint256 _time) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!revealed, "NFTReveal: already revealed");
        revealTime = _time;
    }

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "NFTReveal: fee withdraw failed");
    }

    receive() external payable {}
}
