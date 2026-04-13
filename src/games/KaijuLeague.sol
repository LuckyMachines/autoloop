// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title KaijuLeague (Monster Clash)
 * @author LuckyMachines LLC
 * @notice A persistent monster arena loop where clashes resolve autonomously on an
 *         unchangeable schedule. Entry fees pool into a prize pot, VRF picks
 *         a winner weighted by kaiju health, and all entrants take damage
 *         each clash.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Two independent reasons:
 *
 *      1. TIMING AS ATTACK SURFACE. If any entrant could trigger the clash
 *         themselves they could pick the block in which the VRF reveal
 *         happens. Even though ECVRF is unpredictable given a fixed seed,
 *         the entrant can CHOOSE whether to actually submit based on their
 *         private anticipation of the outcome — a variant of the front-run
 *         problem. A neutral scheduler eliminates this choice.
 *
 *      2. NEGATIVE-EV FREE-RIDER. Every entrant takes damage each clash.
 *         For most entrants the expected value is negative (only one wins the
 *         pot, everyone pays entry + takes damage). The rational move is to
 *         let SOMEONE ELSE trigger the clash so you pay the gas only if you
 *         win. Everyone reasons identically, so nobody triggers. A paid
 *         keeper is the only neutral party whose incentives are aligned
 *         with actually running the loop.
 *
 *      Self-incentivized triggering fails on both counts. AutoLoop is the
 *      only way this game can run fairly and continuously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - hatchFee on every new kaiju                  → protocolFeeBalance
 *      - protocolRakeBps on every clash pot            → protocolFeeBalance
 *      - Non-custodial winnings (pull-payment)         → player mapping
 */
contract KaijuLeague is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event KaijuHatched(
        uint256 indexed kaijuId,
        address indexed owner,
        uint32 initialHealth
    );
    event KaijuEntered(
        uint256 indexed clashId,
        uint256 indexed kaijuId,
        address indexed owner
    );
    event ClashResolved(
        uint256 indexed clashId,
        uint256 indexed winningKaijuId,
        address indexed winner,
        uint256 prize,
        uint256 protocolFee,
        bytes32 randomness
    );
    event DamageDealt(
        uint256 indexed clashId,
        uint256 indexed kaijuId,
        uint32 oldHealth,
        uint32 newHealth
    );
    event WinningsClaimed(address indexed to, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable hatchFee;
    uint256 public immutable entryFee;
    uint256 public immutable clashInterval;
    uint256 public immutable protocolRakeBps;

    uint32 public immutable initialHealth;
    uint32 public immutable minHealth;

    uint256 public immutable maxEntrantsPerClash;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint32 public constant DAMAGE_MIN = 5;
    uint32 public constant DAMAGE_MAX = 20;

    // ===============================================================
    //  State
    // ===============================================================

    struct Kaiju {
        address owner;
        uint32 health;
        uint32 victories;
        uint32 clashes;
    }

    mapping(uint256 => Kaiju) internal _kaijus;
    uint256 public nextKaijuId = 1;

    uint256 public currentClashId = 1;
    /// @notice Maps resolvedClashId → winning kaijuId. Used by KaijuOracle.
    mapping(uint256 => uint256) public clashWinners;
    uint256[] public currentEntrants;
    mapping(uint256 => bool) public enteredInCurrentClash;
    uint256 public currentPrizePool;
    uint256 public lastClashAt;

    uint256 public protocolFeeBalance;
    uint256 public totalClashesResolved;
    uint256 public totalKaijuDestroyed;

    mapping(address => uint256) public pendingWithdrawals;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _hatchFee,
        uint256 _entryFee,
        uint256 _clashInterval,
        uint256 _protocolRakeBps,
        uint32 _initialHealth,
        uint32 _minHealth,
        uint256 _maxEntrantsPerClash
    ) {
        require(_clashInterval > 0, "KaijuLeague: clashInterval=0");
        require(_protocolRakeBps <= 2000, "KaijuLeague: rake > 20%");
        require(_initialHealth > _minHealth, "KaijuLeague: health ordering");
        require(_maxEntrantsPerClash >= 2, "KaijuLeague: maxEntrants < 2");
        require(_maxEntrantsPerClash <= 16, "KaijuLeague: maxEntrants > 16");

        hatchFee = _hatchFee;
        entryFee = _entryFee;
        clashInterval = _clashInterval;
        protocolRakeBps = _protocolRakeBps;
        initialHealth = _initialHealth;
        minHealth = _minHealth;
        maxEntrantsPerClash = _maxEntrantsPerClash;
        lastClashAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Hatch a new kaiju at initialHealth.
    function hatchKaiju() external payable returns (uint256 kaijuId) {
        require(msg.value >= hatchFee, "KaijuLeague: insufficient hatch fee");

        kaijuId = nextKaijuId++;
        _kaijus[kaijuId] = Kaiju({
            owner: _msgSender(),
            health: initialHealth,
            victories: 0,
            clashes: 0
        });
        protocolFeeBalance += hatchFee;

        uint256 overpayment = msg.value - hatchFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "KaijuLeague: refund failed");
        }

        emit KaijuHatched(kaijuId, _msgSender(), initialHealth);
    }

    /// @notice Enter a kaiju in the current clash.
    function enterClash(uint256 kaijuId) external payable {
        require(msg.value >= entryFee, "KaijuLeague: insufficient entry fee");
        Kaiju storage k = _kaijus[kaijuId];
        require(k.owner == _msgSender(), "KaijuLeague: not owner");
        require(k.health >= minHealth, "KaijuLeague: kaiju destroyed");
        require(
            !enteredInCurrentClash[kaijuId],
            "KaijuLeague: already entered"
        );
        require(
            currentEntrants.length < maxEntrantsPerClash,
            "KaijuLeague: clash full"
        );

        currentEntrants.push(kaijuId);
        enteredInCurrentClash[kaijuId] = true;
        currentPrizePool += entryFee;

        uint256 overpayment = msg.value - entryFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "KaijuLeague: refund failed");
        }

        emit KaijuEntered(currentClashId, kaijuId, _msgSender());
    }

    /// @notice Pull-payment winnings claim.
    function claimWinnings() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "KaijuLeague: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "KaijuLeague: withdraw failed");
        emit WinningsClaimed(_msgSender(), amount);
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
            (block.timestamp >= lastClashAt + clashInterval) &&
            (currentEntrants.length >= 2);
        progressWithData = abi.encode(_loopID);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness, bytes memory gameData) = _verifyAndExtractRandomness(
            progressWithData,
            tx.origin
        );
        uint256 loopID = abi.decode(gameData, (uint256));
        _progressInternal(randomness, loopID);
    }

    function _progressInternal(bytes32 randomness, uint256 loopID) internal {
        require(
            block.timestamp >= lastClashAt + clashInterval,
            "KaijuLeague: too soon"
        );
        require(loopID == _loopID, "KaijuLeague: stale loop id");
        require(
            currentEntrants.length >= 2,
            "KaijuLeague: not enough entrants"
        );

        // ---- Pick winner weighted by health ----
        uint256 totalHealth = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalHealth += uint256(_kaijus[currentEntrants[i]].health);
        }
        uint256 r = uint256(randomness);
        uint256 winningWeight = r % totalHealth;

        uint256 winnerId;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += uint256(_kaijus[currentEntrants[i]].health);
            if (cumulative > winningWeight) {
                winnerId = currentEntrants[i];
                break;
            }
        }

        // ---- Split pot ----
        uint256 pot = currentPrizePool;
        uint256 protocolCut = (pot * protocolRakeBps) / BPS_DENOMINATOR;
        uint256 prize = pot - protocolCut;
        protocolFeeBalance += protocolCut;
        Kaiju storage winner = _kaijus[winnerId];
        pendingWithdrawals[winner.owner] += prize;
        winner.victories++;
        clashWinners[currentClashId] = winnerId;

        emit ClashResolved(
            currentClashId,
            winnerId,
            winner.owner,
            prize,
            protocolCut,
            randomness
        );

        // ---- Deal damage to all entrants ----
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Kaiju storage k = _kaijus[entrantId];
            k.clashes++;

            uint256 damageRoll = uint256(
                keccak256(abi.encodePacked(randomness, entrantId, "stomp"))
            );
            uint32 damageRange = DAMAGE_MAX - DAMAGE_MIN + 1;
            uint32 damageAmount = uint32(DAMAGE_MIN + (damageRoll % damageRange));

            uint32 oldHealth = k.health;
            uint32 newHealth;
            if (k.health > damageAmount + minHealth) {
                newHealth = k.health - damageAmount;
            } else {
                newHealth = minHealth;
                totalKaijuDestroyed++;
            }
            k.health = newHealth;
            emit DamageDealt(currentClashId, entrantId, oldHealth, newHealth);

            enteredInCurrentClash[entrantId] = false;
        }

        // ---- Advance state ----
        lastClashAt = block.timestamp;
        totalClashesResolved++;
        currentClashId++;
        delete currentEntrants;
        currentPrizePool = 0;
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getKaiju(uint256 kaijuId) external view returns (Kaiju memory) {
        return _kaijus[kaijuId];
    }

    function currentEntrantCount() external view returns (uint256) {
        return currentEntrants.length;
    }

    function currentLoopID() external view returns (uint256) {
        return _loopID;
    }

    // ===============================================================
    //  Admin
    // ===============================================================

    function withdrawProtocolFees(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "KaijuLeague: zero address");
        require(amount <= protocolFeeBalance, "KaijuLeague: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "KaijuLeague: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
