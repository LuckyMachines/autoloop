// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../AutoLoopVRFCompatible.sol";

/// @title BreedingMutationEngine
/// @notice Queue-based NFT breeding: owners pair two parent tokens, pay a fee, and the
///         AutoLoop keeper processes the queue with VRF to determine offspring traits.
///         Self-triggering is fatal: the trigger holder can preview trait outcomes from the
///         VRF output before submitting. They simply wait until a favorable roll appears —
///         rare traits stay rare only if nobody can filter.
/// @dev Demonstrates: genetic randomness as a front-running target.
contract BreedingMutationEngine is AutoLoopVRFCompatible {
    // ── Constants ──────────────────────────────────────────────────────────────

    uint256 public constant NUM_TRAITS       = 5;
    uint256 public constant MUTATION_RATE_BPS = 500;  // 5% per trait
    uint256 public constant PROTOCOL_FEE_BPS  = 200;  // 2%

    string[5] public traitNames; // set in constructor

    // ── Types ──────────────────────────────────────────────────────────────────

    struct BreedingPair {
        uint256 parent1;
        uint256 parent2;
        address owner;
        uint256 queuedAt;
    }

    // ── State ──────────────────────────────────────────────────────────────────

    mapping(uint256 => uint8[5]) public traits;   // tokenId → [0..99] per trait
    mapping(uint256 => address)  public ownerOf;

    uint256 public nextTokenId;
    uint256 public breedingCooldown;
    uint256 public breedingFee;
    uint256 public lastBreed;

    uint256 public protocolFeeBalance;

    BreedingPair[] public breedingQueue;

    // ── Events ─────────────────────────────────────────────────────────────────

    event TokenMinted(uint256 indexed tokenId, address indexed owner, uint8[5] traits);
    event BreedingQueued(uint256 indexed pairId, uint256 parent1, uint256 parent2, address owner);
    event BreedingComplete(uint256 indexed parent1, uint256 indexed parent2, uint256 indexed offspringId, uint8[5] offspringTraits);

    // ── Construction ───────────────────────────────────────────────────────────

    /// @param _breedingCooldown Minimum seconds between breeding ticks
    /// @param _breedingFee      Wei required to queue a breeding pair
    constructor(uint256 _breedingCooldown, uint256 _breedingFee) {
        require(_breedingCooldown > 0, "BreedingEngine: cooldown=0");
        breedingCooldown = _breedingCooldown;
        breedingFee      = _breedingFee;
        lastBreed        = block.timestamp;
        traitNames[0] = "Strength";
        traitNames[1] = "Speed";
        traitNames[2] = "Stamina";
        traitNames[3] = "Intelligence";
        traitNames[4] = "Luck";
    }

    // ── Player actions ─────────────────────────────────────────────────────────

    /// @notice Mint a genesis token. Traits seeded from block hash (weak, but genesis only).
    function mint() external payable returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        ownerOf[tokenId] = msg.sender;
        uint8[5] memory t;
        bytes32 seed = keccak256(abi.encodePacked(blockhash(block.number - 1), tokenId, msg.sender));
        for (uint256 i = 0; i < NUM_TRAITS; i++) {
            t[i] = uint8((uint256(keccak256(abi.encodePacked(seed, i))) % 100) + 1); // 1..100
        }
        traits[tokenId] = t;
        emit TokenMinted(tokenId, msg.sender, t);
    }

    /// @notice Queue a breeding pair. Caller must own both parents.
    function queueBreeding(uint256 parent1, uint256 parent2) external payable returns (uint256 pairId) {
        require(ownerOf[parent1] == msg.sender, "BreedingEngine: not owner of parent1");
        require(ownerOf[parent2] == msg.sender, "BreedingEngine: not owner of parent2");
        require(parent1 != parent2, "BreedingEngine: same token");
        require(msg.value >= breedingFee, "BreedingEngine: insufficient fee");

        uint256 fee = (msg.value * PROTOCOL_FEE_BPS) / 10_000;
        protocolFeeBalance += fee;

        pairId = breedingQueue.length;
        breedingQueue.push(BreedingPair({
            parent1:  parent1,
            parent2:  parent2,
            owner:    msg.sender,
            queuedAt: block.timestamp
        }));
        emit BreedingQueued(pairId, parent1, parent2, msg.sender);
    }

    // ── Keeper interface ───────────────────────────────────────────────────────

    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = breedingQueue.length > 0
            && (block.timestamp - lastBreed) >= breedingCooldown;
        progressWithData = abi.encode(_loopID, breedingQueue.length);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness,) = _verifyAndExtractRandomness(progressWithData, msg.sender);

        require(breedingQueue.length > 0, "BreedingEngine: queue empty");
        require((block.timestamp - lastBreed) >= breedingCooldown, "BreedingEngine: too soon");

        lastBreed = block.timestamp;
        ++_loopID;

        _processFirstPair(randomness);
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    function _processFirstPair(bytes32 randomness) internal {
        // Process first pair and remove it (swap-and-pop)
        BreedingPair memory pair = breedingQueue[0];
        uint256 lastIdx = breedingQueue.length - 1;
        if (lastIdx > 0) breedingQueue[0] = breedingQueue[lastIdx];
        breedingQueue.pop();

        uint8[5] memory p1Traits = traits[pair.parent1];
        uint8[5] memory p2Traits = traits[pair.parent2];

        uint256 tokenId = nextTokenId++;
        ownerOf[tokenId] = pair.owner;

        uint8[5] memory offspringTraits;
        for (uint256 i = 0; i < NUM_TRAITS; i++) {
            bytes32 traitRand = keccak256(abi.encodePacked(randomness, i));
            uint256 roll = uint256(traitRand) % 10_000;
            if (roll < MUTATION_RATE_BPS) {
                // Mutation: random value 1..100
                offspringTraits[i] = uint8((uint256(keccak256(abi.encodePacked(traitRand, "mut"))) % 100) + 1);
            } else {
                // Inherit from one parent
                offspringTraits[i] = (uint256(keccak256(abi.encodePacked(traitRand, "inh"))) % 2 == 0)
                    ? p1Traits[i]
                    : p2Traits[i];
            }
        }

        traits[tokenId] = offspringTraits;
        emit BreedingComplete(pair.parent1, pair.parent2, tokenId, offspringTraits);
        emit TokenMinted(tokenId, pair.owner, offspringTraits);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setBreedingCooldown(uint256 _cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_cooldown > 0, "BreedingEngine: cooldown=0");
        breedingCooldown = _cooldown;
    }

    function setBreedingFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        breedingFee = _fee;
    }

    function withdrawProtocolFees(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = protocolFeeBalance;
        protocolFeeBalance = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "BreedingEngine: fee withdraw failed");
    }

    // ── Views ──────────────────────────────────────────────────────────────────

    function getTraits(uint256 tokenId) external view returns (uint8[5] memory) {
        return traits[tokenId];
    }

    function queueLength() external view returns (uint256) {
        return breedingQueue.length;
    }

    receive() external payable {}
}
