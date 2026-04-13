// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title GladiatorArena (Eternal Bout)
 * @author LuckyMachines LLC
 * @notice A persistent colosseum loop where bouts resolve autonomously on an
 *         unchangeable schedule. Entry fees pool into a prize pot, VRF picks
 *         a victor weighted by gladiator vitality, and all entrants take
 *         wounds each bout.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Two independent reasons:
 *
 *      1. TIMING AS ATTACK SURFACE. If any entrant could trigger the bout
 *         themselves they could pick the block in which the VRF reveal
 *         happens. Even though ECVRF is unpredictable given a fixed seed,
 *         the entrant can CHOOSE whether to actually submit based on their
 *         private anticipation of the outcome — a variant of the front-run
 *         problem. A neutral scheduler eliminates this choice.
 *
 *      2. NEGATIVE-EV FREE-RIDER. Every entrant takes wound damage each bout.
 *         For most entrants the expected value is negative (only one wins the
 *         pot, everyone pays entry + takes wounds). The rational move is to
 *         let SOMEONE ELSE trigger the bout so you pay the gas only if you
 *         win. Everyone reasons identically, so nobody triggers. A paid
 *         keeper is the only neutral party whose incentives are aligned
 *         with actually running the loop.
 *
 *      Self-incentivized triggering fails on both counts. AutoLoop is the
 *      only way this game can run fairly and continuously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - gladiatorMintFee on every new gladiator      → protocolFeeBalance
 *      - protocolRakeBps on every bout pot             → protocolFeeBalance
 *      - Non-custodial winnings (pull-payment)         → player mapping
 */
contract GladiatorArena is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event GladiatorMinted(
        uint256 indexed gladiatorId,
        address indexed owner,
        uint32 initialVitality
    );
    event GladiatorEntered(
        uint256 indexed boutId,
        uint256 indexed gladiatorId,
        address indexed owner
    );
    event BoutResolved(
        uint256 indexed boutId,
        uint256 indexed winningGladiatorId,
        address indexed winner,
        uint256 prize,
        uint256 protocolFee,
        bytes32 randomness
    );
    event WoundsDealt(
        uint256 indexed boutId,
        uint256 indexed gladiatorId,
        uint32 oldVitality,
        uint32 newVitality
    );
    event VictoryClaimed(address indexed to, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable gladiatorMintFee;
    uint256 public immutable entryFee;
    uint256 public immutable boutInterval;
    uint256 public immutable protocolRakeBps;

    uint32 public immutable initialVitality;
    uint32 public immutable minVitality;

    uint256 public immutable maxEntrantsPerBout;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint32 public constant WOUND_MIN = 5;
    uint32 public constant WOUND_MAX = 20;

    // ===============================================================
    //  State
    // ===============================================================

    struct Gladiator {
        address owner;
        uint32 vitality;
        uint32 victories;
        uint32 bouts;
    }

    mapping(uint256 => Gladiator) internal _gladiators;
    uint256 public nextGladiatorId = 1;

    uint256 public currentBoutId = 1;
    uint256[] public currentEntrants;
    mapping(uint256 => bool) public enteredInCurrentBout;
    uint256 public currentPrizePool;
    uint256 public lastBoutAt;

    uint256 public protocolFeeBalance;
    uint256 public totalBoutsResolved;
    uint256 public totalGladiatorsFallen;

    mapping(address => uint256) public pendingWithdrawals;
    /// @notice Maps completedBoutId → winning gladiatorId. Used by GladiatorOracle.
    mapping(uint256 => uint256) public boutWinners;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _gladiatorMintFee,
        uint256 _entryFee,
        uint256 _boutInterval,
        uint256 _protocolRakeBps,
        uint32 _initialVitality,
        uint32 _minVitality,
        uint256 _maxEntrantsPerBout
    ) {
        require(_boutInterval > 0, "GladiatorArena: boutInterval=0");
        require(_protocolRakeBps <= 2000, "GladiatorArena: rake > 20%");
        require(_initialVitality > _minVitality, "GladiatorArena: vitality ordering");
        require(_maxEntrantsPerBout >= 2, "GladiatorArena: maxEntrants < 2");
        require(_maxEntrantsPerBout <= 16, "GladiatorArena: maxEntrants > 16");

        gladiatorMintFee = _gladiatorMintFee;
        entryFee = _entryFee;
        boutInterval = _boutInterval;
        protocolRakeBps = _protocolRakeBps;
        initialVitality = _initialVitality;
        minVitality = _minVitality;
        maxEntrantsPerBout = _maxEntrantsPerBout;
        lastBoutAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Mint a new gladiator at initialVitality.
    function mintGladiator() external payable returns (uint256 gladiatorId) {
        require(msg.value >= gladiatorMintFee, "GladiatorArena: insufficient mint fee");

        gladiatorId = nextGladiatorId++;
        _gladiators[gladiatorId] = Gladiator({
            owner: _msgSender(),
            vitality: initialVitality,
            victories: 0,
            bouts: 0
        });
        protocolFeeBalance += gladiatorMintFee;

        uint256 overpayment = msg.value - gladiatorMintFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "GladiatorArena: refund failed");
        }

        emit GladiatorMinted(gladiatorId, _msgSender(), initialVitality);
    }

    /// @notice Enter a gladiator in the current bout.
    function enterBout(uint256 gladiatorId) external payable {
        require(msg.value >= entryFee, "GladiatorArena: insufficient entry fee");
        Gladiator storage g = _gladiators[gladiatorId];
        require(g.owner == _msgSender(), "GladiatorArena: not owner");
        require(g.vitality >= minVitality, "GladiatorArena: gladiator retired");
        require(
            !enteredInCurrentBout[gladiatorId],
            "GladiatorArena: already entered"
        );
        require(
            currentEntrants.length < maxEntrantsPerBout,
            "GladiatorArena: bout full"
        );

        currentEntrants.push(gladiatorId);
        enteredInCurrentBout[gladiatorId] = true;
        currentPrizePool += entryFee;

        uint256 overpayment = msg.value - entryFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "GladiatorArena: refund failed");
        }

        emit GladiatorEntered(currentBoutId, gladiatorId, _msgSender());
    }

    /// @notice Pull-payment winnings claim.
    function claimVictory() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "GladiatorArena: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "GladiatorArena: withdraw failed");
        emit VictoryClaimed(_msgSender(), amount);
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
            (block.timestamp >= lastBoutAt + boutInterval) &&
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
            block.timestamp >= lastBoutAt + boutInterval,
            "GladiatorArena: too soon"
        );
        require(loopID == _loopID, "GladiatorArena: stale loop id");
        require(
            currentEntrants.length >= 2,
            "GladiatorArena: not enough entrants"
        );

        // ---- Pick victor weighted by vitality ----
        uint256 totalVitality = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalVitality += uint256(_gladiators[currentEntrants[i]].vitality);
        }
        uint256 r = uint256(randomness);
        uint256 winningWeight = r % totalVitality;

        uint256 winnerId;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += uint256(_gladiators[currentEntrants[i]].vitality);
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
        Gladiator storage winner = _gladiators[winnerId];
        pendingWithdrawals[winner.owner] += prize;
        winner.victories++;
        boutWinners[currentBoutId] = winnerId;

        emit BoutResolved(
            currentBoutId,
            winnerId,
            winner.owner,
            prize,
            protocolCut,
            randomness
        );

        // ---- Apply wounds to all entrants ----
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Gladiator storage g = _gladiators[entrantId];
            g.bouts++;

            uint256 woundRoll = uint256(
                keccak256(abi.encodePacked(randomness, entrantId, "wound"))
            );
            uint32 woundRange = WOUND_MAX - WOUND_MIN + 1;
            uint32 woundAmount = uint32(WOUND_MIN + (woundRoll % woundRange));

            uint32 oldVitality = g.vitality;
            uint32 newVitality;
            if (g.vitality > woundAmount + minVitality) {
                newVitality = g.vitality - woundAmount;
            } else {
                newVitality = minVitality;
                totalGladiatorsFallen++;
            }
            g.vitality = newVitality;
            emit WoundsDealt(currentBoutId, entrantId, oldVitality, newVitality);

            enteredInCurrentBout[entrantId] = false;
        }

        // ---- Advance state ----
        lastBoutAt = block.timestamp;
        totalBoutsResolved++;
        currentBoutId++;
        delete currentEntrants;
        currentPrizePool = 0;
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getGladiator(uint256 gladiatorId) external view returns (Gladiator memory) {
        return _gladiators[gladiatorId];
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
        require(to != address(0), "GladiatorArena: zero address");
        require(amount <= protocolFeeBalance, "GladiatorArena: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "GladiatorArena: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
