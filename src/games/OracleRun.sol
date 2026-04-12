// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title OracleRun (Autonomous Dungeon Crawl)
 * @author LuckyMachines LLC
 * @notice A permadeath dungeon runs autonomously on an unchangeable schedule.
 *         Players mint characters, register them for an expedition by paying
 *         an entry fee, and the expedition resolves on the next VRF tick:
 *         each character rolls against the floor's VRF-derived difficulty.
 *         Survivors split the prize pool; dead characters are permanently
 *         flagged (no resurrection in v1).
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      1. MEMPOOL-SNOOPING ATTACK. If a player controlled the trigger, they
 *         could watch the mempool for their own "ready to resolve" tx,
 *         compute what the resulting difficulty would be for each character,
 *         and only submit if their character is favored. A neutral
 *         scheduler eliminates the attack.
 *
 *      2. DEATH-STALLING. A player whose character is borderline wants to
 *         delay resolution indefinitely. A player whose character is strong
 *         wants resolution now. The only neutral resolver is a paid keeper.
 *
 *      3. FORFEIT FLOOR. The expedition floor advances by VRF TIER every
 *         round, accumulating higher stakes. If any player could trigger
 *         advancement, they could camp forever at a low-difficulty floor.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - characterMintFee on mint       → protocolFeeBalance
 *      - entryFee rake on each expedition → protocolFeeBalance
 *      - Dead characters' stakes          → survivors' pot (losers fund winners)
 *      - Floors with no survivors         → entire pot to protocol
 */
contract OracleRun is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event CharacterMinted(
        uint256 indexed characterId,
        address indexed owner,
        uint32 power
    );
    event CharacterRegistered(
        uint256 indexed expeditionId,
        uint256 indexed characterId,
        address indexed owner,
        uint256 stake
    );
    event ExpeditionResolved(
        uint256 indexed expeditionId,
        uint32 difficulty,
        uint256 survivorCount,
        uint256 casualtyCount,
        uint256 prizePool,
        uint256 protocolFee,
        bytes32 randomness
    );
    event CharacterSurvived(
        uint256 indexed expeditionId,
        uint256 indexed characterId,
        uint32 roll,
        uint256 payout
    );
    event CharacterDied(
        uint256 indexed expeditionId,
        uint256 indexed characterId,
        uint32 roll
    );
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable characterMintFee;
    uint256 public immutable entryFee;
    uint256 public immutable expeditionInterval;
    uint256 public immutable protocolRakeBps;
    uint32 public immutable baseDifficulty;
    uint32 public immutable difficultyPerFloor;
    uint32 public immutable initialPower;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_ENTRANTS = 16;
    uint32 public constant ROLL_MAX = 1000;

    // ===============================================================
    //  State
    // ===============================================================

    struct Character {
        address owner;
        uint32 power;
        uint32 expeditionsSurvived;
        bool dead;
        bool registered; // registered for current expedition
    }

    mapping(uint256 => Character) internal _characters;
    uint256 public nextCharacterId = 1;

    uint256 public currentExpeditionId = 1;
    uint256[] public currentEntrants;
    uint256 public currentPool;
    uint256 public lastExpeditionAt;
    uint32 public currentFloor = 1;

    uint256 public protocolFeeBalance;
    uint256 public totalExpeditionsResolved;

    mapping(address => uint256) public pendingWithdrawals;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _characterMintFee,
        uint256 _entryFee,
        uint256 _expeditionInterval,
        uint256 _protocolRakeBps,
        uint32 _baseDifficulty,
        uint32 _difficultyPerFloor,
        uint32 _initialPower
    ) {
        require(_expeditionInterval > 0, "OracleRun: interval=0");
        require(_protocolRakeBps <= 2000, "OracleRun: rake > 20%");
        require(_baseDifficulty < ROLL_MAX, "OracleRun: base >= max roll");
        require(_initialPower > 0, "OracleRun: power=0");
        characterMintFee = _characterMintFee;
        entryFee = _entryFee;
        expeditionInterval = _expeditionInterval;
        protocolRakeBps = _protocolRakeBps;
        baseDifficulty = _baseDifficulty;
        difficultyPerFloor = _difficultyPerFloor;
        initialPower = _initialPower;
        lastExpeditionAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    function mintCharacter() external payable returns (uint256 characterId) {
        require(msg.value >= characterMintFee, "OracleRun: insufficient fee");
        characterId = nextCharacterId++;
        _characters[characterId] = Character({
            owner: _msgSender(),
            power: initialPower,
            expeditionsSurvived: 0,
            dead: false,
            registered: false
        });
        protocolFeeBalance += characterMintFee;

        uint256 overpayment = msg.value - characterMintFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "OracleRun: refund failed");
        }
        emit CharacterMinted(characterId, _msgSender(), initialPower);
    }

    function registerForExpedition(uint256 characterId) external payable {
        require(msg.value >= entryFee, "OracleRun: insufficient entry fee");
        Character storage c = _characters[characterId];
        require(c.owner == _msgSender(), "OracleRun: not owner");
        require(!c.dead, "OracleRun: character dead");
        require(!c.registered, "OracleRun: already registered");
        require(
            currentEntrants.length < MAX_ENTRANTS,
            "OracleRun: expedition full"
        );

        c.registered = true;
        currentEntrants.push(characterId);
        currentPool += entryFee;

        uint256 overpayment = msg.value - entryFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "OracleRun: refund failed");
        }

        emit CharacterRegistered(
            currentExpeditionId,
            characterId,
            _msgSender(),
            entryFee
        );
    }

    function claimWinnings() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "OracleRun: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "OracleRun: withdraw failed");
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
        loopIsReady =
            block.timestamp >= lastExpeditionAt + expeditionInterval &&
            currentEntrants.length > 0;
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
        require(loopID == _loopID, "OracleRun: stale loop id");
        require(
            block.timestamp >= lastExpeditionAt + expeditionInterval,
            "OracleRun: too soon"
        );
        require(currentEntrants.length > 0, "OracleRun: no entrants");

        // Compute floor difficulty — higher floors are harder
        uint32 difficulty = baseDifficulty +
            (currentFloor - 1) *
            difficultyPerFloor;
        if (difficulty >= ROLL_MAX) difficulty = ROLL_MAX - 1;

        // First pass: determine survivors
        uint256[] memory survivors = new uint256[](currentEntrants.length);
        uint256 survivorCount = 0;
        uint256 casualtyCount = 0;

        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Character storage c = _characters[entrantId];

            uint32 roll = uint32(
                uint256(
                    keccak256(abi.encodePacked(randomness, entrantId, "roll"))
                ) % ROLL_MAX
            );

            // Survival: roll + power beats difficulty
            if (uint256(roll) + uint256(c.power) > uint256(difficulty)) {
                survivors[survivorCount++] = entrantId;
                c.expeditionsSurvived++;
                emit CharacterSurvived(
                    currentExpeditionId,
                    entrantId,
                    roll,
                    0 /* payout computed below */
                );
            } else {
                c.dead = true;
                casualtyCount++;
                emit CharacterDied(currentExpeditionId, entrantId, roll);
            }

            c.registered = false;
        }

        // Second pass: distribute pool
        uint256 protocolCut = (currentPool * protocolRakeBps) /
            BPS_DENOMINATOR;
        uint256 prizePool = currentPool - protocolCut;
        protocolFeeBalance += protocolCut;

        if (survivorCount == 0) {
            // Entire prize goes to protocol (plus the rake already added)
            protocolFeeBalance += prizePool;
        } else {
            uint256 perSurvivor = prizePool / survivorCount;
            uint256 remainder = prizePool - perSurvivor * survivorCount;
            for (uint256 i = 0; i < survivorCount; i++) {
                Character storage sc = _characters[survivors[i]];
                pendingWithdrawals[sc.owner] += perSurvivor;
            }
            // Remainder dust goes to protocol to avoid rounding loss
            protocolFeeBalance += remainder;
        }

        emit ExpeditionResolved(
            currentExpeditionId,
            difficulty,
            survivorCount,
            casualtyCount,
            currentPool,
            protocolCut,
            randomness
        );

        // Advance state
        lastExpeditionAt = block.timestamp;
        totalExpeditionsResolved++;
        currentExpeditionId++;
        delete currentEntrants;
        currentPool = 0;
        // If at least one character survived, advance the floor to ratchet
        // difficulty upward. This is the "progression loop" that nobody wants
        // to trigger late-game.
        if (survivorCount > 0) {
            currentFloor++;
        }
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getCharacter(
        uint256 characterId
    ) external view returns (Character memory) {
        return _characters[characterId];
    }

    function currentEntrantCount() external view returns (uint256) {
        return currentEntrants.length;
    }

    function currentLoopID() external view returns (uint256) {
        return _loopID;
    }

    function currentDifficulty() external view returns (uint32) {
        uint32 d = baseDifficulty + (currentFloor - 1) * difficultyPerFloor;
        if (d >= ROLL_MAX) return ROLL_MAX - 1;
        return d;
    }

    // ===============================================================
    //  Admin
    // ===============================================================

    function withdrawProtocolFees(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "OracleRun: zero address");
        require(amount <= protocolFeeBalance, "OracleRun: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "OracleRun: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
