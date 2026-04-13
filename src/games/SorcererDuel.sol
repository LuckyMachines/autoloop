// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title SorcererDuel (Arcane Circle)
 * @author LuckyMachines LLC
 * @notice A persistent sorcery loop where duels resolve autonomously on an
 *         unchangeable schedule. Stakes pool into a prize pot, VRF picks
 *         a winner weighted by sorcerer mana, and all entrants lose mana
 *         each duel.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Two independent reasons:
 *
 *      1. TIMING AS ATTACK SURFACE. If any entrant could trigger the duel
 *         themselves they could pick the block in which the VRF reveal
 *         happens. Even though ECVRF is unpredictable given a fixed seed,
 *         the entrant can CHOOSE whether to actually submit based on their
 *         private anticipation of the outcome — a variant of the front-run
 *         problem. A neutral scheduler eliminates this choice.
 *
 *      2. NEGATIVE-EV FREE-RIDER. Every entrant loses mana each duel.
 *         For most entrants the expected value is negative (only one wins the
 *         pot, everyone pays entry + loses mana). The rational move is to
 *         let SOMEONE ELSE trigger the duel so you pay the gas only if you
 *         win. Everyone reasons identically, so nobody triggers. A paid
 *         keeper is the only neutral party whose incentives are aligned
 *         with actually running the loop.
 *
 *      Self-incentivized triggering fails on both counts. AutoLoop is the
 *      only way this game can run fairly and continuously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - summonFee on every new sorcerer               → protocolFeeBalance
 *      - protocolRakeBps on every duel pot              → protocolFeeBalance
 *      - Non-custodial winnings (pull-payment)          → player mapping
 */
contract SorcererDuel is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event SorcererSummoned(
        uint256 indexed sorcererId,
        address indexed owner,
        uint32 initialMana
    );
    event SorcererEntered(
        uint256 indexed duelId,
        uint256 indexed sorcererId,
        address indexed owner
    );
    event DuelResolved(
        uint256 indexed duelId,
        uint256 indexed winningSorcererId,
        address indexed winner,
        uint256 prize,
        uint256 protocolFee,
        bytes32 randomness
    );
    event ManaDrained(
        uint256 indexed duelId,
        uint256 indexed sorcererId,
        uint32 oldMana,
        uint32 newMana
    );
    event WinningsClaimed(address indexed to, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable summonFee;
    uint256 public immutable entryFee;
    uint256 public immutable duelInterval;
    uint256 public immutable protocolRakeBps;

    uint32 public immutable initialMana;
    uint32 public immutable minMana;

    uint256 public immutable maxDuelists;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint32 public constant DRAIN_MIN = 5;
    uint32 public constant DRAIN_MAX = 20;

    // ===============================================================
    //  State
    // ===============================================================

    struct Sorcerer {
        address owner;
        uint32 mana;
        uint32 victories;
        uint32 duels;
    }

    mapping(uint256 => Sorcerer) internal _sorcerers;
    uint256 public nextSorcererId = 1;

    uint256 public currentDuelId = 1;
    uint256[] public currentEntrants;
    mapping(uint256 => bool) public enteredInCurrentDuel;
    uint256 public currentPrizePool;
    uint256 public lastDuelAt;

    uint256 public protocolFeeBalance;
    uint256 public totalDuelsResolved;
    uint256 public totalSorcerersBanished;

    mapping(address => uint256) public pendingWithdrawals;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _summonFee,
        uint256 _entryFee,
        uint256 _duelInterval,
        uint256 _protocolRakeBps,
        uint32 _initialMana,
        uint32 _minMana,
        uint256 _maxDuelists
    ) {
        require(_duelInterval > 0, "SorcererDuel: duelInterval=0");
        require(_protocolRakeBps <= 2000, "SorcererDuel: rake > 20%");
        require(_initialMana > _minMana, "SorcererDuel: mana ordering");
        require(_maxDuelists >= 2, "SorcererDuel: maxEntrants < 2");
        require(_maxDuelists <= 16, "SorcererDuel: maxEntrants > 16");

        summonFee = _summonFee;
        entryFee = _entryFee;
        duelInterval = _duelInterval;
        protocolRakeBps = _protocolRakeBps;
        initialMana = _initialMana;
        minMana = _minMana;
        maxDuelists = _maxDuelists;
        lastDuelAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Summon a new sorcerer at initialMana.
    function summonSorcerer() external payable returns (uint256 sorcererId) {
        require(msg.value >= summonFee, "SorcererDuel: insufficient summon fee");

        sorcererId = nextSorcererId++;
        _sorcerers[sorcererId] = Sorcerer({
            owner: _msgSender(),
            mana: initialMana,
            victories: 0,
            duels: 0
        });
        protocolFeeBalance += summonFee;

        uint256 overpayment = msg.value - summonFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "SorcererDuel: refund failed");
        }

        emit SorcererSummoned(sorcererId, _msgSender(), initialMana);
    }

    /// @notice Enter a sorcerer in the current duel.
    function enterDuel(uint256 sorcererId) external payable {
        require(msg.value >= entryFee, "SorcererDuel: insufficient entry fee");
        Sorcerer storage s = _sorcerers[sorcererId];
        require(s.owner == _msgSender(), "SorcererDuel: not owner");
        require(s.mana >= minMana, "SorcererDuel: sorcerer banished");
        require(
            !enteredInCurrentDuel[sorcererId],
            "SorcererDuel: already entered"
        );
        require(
            currentEntrants.length < maxDuelists,
            "SorcererDuel: duel full"
        );

        currentEntrants.push(sorcererId);
        enteredInCurrentDuel[sorcererId] = true;
        currentPrizePool += entryFee;

        uint256 overpayment = msg.value - entryFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "SorcererDuel: refund failed");
        }

        emit SorcererEntered(currentDuelId, sorcererId, _msgSender());
    }

    /// @notice Pull-payment winnings claim.
    function claimWinnings() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "SorcererDuel: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "SorcererDuel: withdraw failed");
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
            (block.timestamp >= lastDuelAt + duelInterval) &&
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
            block.timestamp >= lastDuelAt + duelInterval,
            "SorcererDuel: too soon"
        );
        require(loopID == _loopID, "SorcererDuel: stale loop id");
        require(
            currentEntrants.length >= 2,
            "SorcererDuel: not enough entrants"
        );

        // ---- Pick winner weighted by mana ----
        uint256 totalMana = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalMana += uint256(_sorcerers[currentEntrants[i]].mana);
        }
        uint256 r = uint256(randomness);
        uint256 winningWeight = r % totalMana;

        uint256 winnerId;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += uint256(_sorcerers[currentEntrants[i]].mana);
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
        Sorcerer storage winner = _sorcerers[winnerId];
        pendingWithdrawals[winner.owner] += prize;
        winner.victories++;

        emit DuelResolved(
            currentDuelId,
            winnerId,
            winner.owner,
            prize,
            protocolCut,
            randomness
        );

        // ---- Drain mana from all entrants ----
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Sorcerer storage s = _sorcerers[entrantId];
            s.duels++;

            uint256 drainRoll = uint256(
                keccak256(abi.encodePacked(randomness, entrantId, "drain"))
            );
            uint32 drainRange = DRAIN_MAX - DRAIN_MIN + 1;
            uint32 drainAmount = uint32(DRAIN_MIN + (drainRoll % drainRange));

            uint32 oldMana = s.mana;
            uint32 newMana;
            if (s.mana > drainAmount + minMana) {
                newMana = s.mana - drainAmount;
            } else {
                newMana = minMana;
                totalSorcerersBanished++;
            }
            s.mana = newMana;
            emit ManaDrained(currentDuelId, entrantId, oldMana, newMana);

            enteredInCurrentDuel[entrantId] = false;
        }

        // ---- Advance state ----
        lastDuelAt = block.timestamp;
        totalDuelsResolved++;
        currentDuelId++;
        delete currentEntrants;
        currentPrizePool = 0;
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getSorcerer(uint256 sorcererId) external view returns (Sorcerer memory) {
        return _sorcerers[sorcererId];
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
        require(to != address(0), "SorcererDuel: zero address");
        require(amount <= protocolFeeBalance, "SorcererDuel: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "SorcererDuel: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
