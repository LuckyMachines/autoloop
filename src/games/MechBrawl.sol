// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title MechBrawl (Iron Pit)
 * @author LuckyMachines LLC
 * @notice A persistent mech arena loop where brawls resolve autonomously on an
 *         unchangeable schedule. Entry fees pool into a prize pot, VRF picks
 *         a winner weighted by mech armor, and all entrants take hull damage
 *         each brawl.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Two independent reasons:
 *
 *      1. TIMING AS ATTACK SURFACE. If any entrant could trigger the brawl
 *         themselves they could pick the block in which the VRF reveal
 *         happens. Even though ECVRF is unpredictable given a fixed seed,
 *         the entrant can CHOOSE whether to actually submit based on their
 *         private anticipation of the outcome — a variant of the front-run
 *         problem. A neutral scheduler eliminates this choice.
 *
 *      2. NEGATIVE-EV FREE-RIDER. Every entrant takes hull damage each brawl.
 *         For most entrants the expected value is negative (only one wins the
 *         pot, everyone pays entry + takes damage). The rational move is to
 *         let SOMEONE ELSE trigger the brawl so you pay the gas only if you
 *         win. Everyone reasons identically, so nobody triggers. A paid
 *         keeper is the only neutral party whose incentives are aligned
 *         with actually running the loop.
 *
 *      Self-incentivized triggering fails on both counts. AutoLoop is the
 *      only way this game can run fairly and continuously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - deployFee on every new mech                → protocolFeeBalance
 *      - protocolRakeBps on every brawl pot          → protocolFeeBalance
 *      - Non-custodial winnings (pull-payment)       → player mapping
 */
contract MechBrawl is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event MechDeployed(
        uint256 indexed mechId,
        address indexed owner,
        uint32 initialArmor
    );
    event MechJoined(
        uint256 indexed brawlId,
        uint256 indexed mechId,
        address indexed owner
    );
    event BrawlResolved(
        uint256 indexed brawlId,
        uint256 indexed winningMechId,
        address indexed winner,
        uint256 prize,
        uint256 protocolFee,
        bytes32 randomness
    );
    event HullDamaged(
        uint256 indexed brawlId,
        uint256 indexed mechId,
        uint32 oldArmor,
        uint32 newArmor
    );
    event WinningsClaimed(address indexed to, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable deployFee;
    uint256 public immutable entryFee;
    uint256 public immutable brawlInterval;
    uint256 public immutable protocolRakeBps;

    uint32 public immutable initialArmor;
    uint32 public immutable minArmor;

    uint256 public immutable maxEntrantsPerBrawl;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint32 public constant DAMAGE_MIN = 5;
    uint32 public constant DAMAGE_MAX = 20;

    // ===============================================================
    //  State
    // ===============================================================

    struct Mech {
        address owner;
        uint32 armor;
        uint32 victories;
        uint32 brawls;
    }

    mapping(uint256 => Mech) internal _mechs;
    uint256 public nextMechId = 1;

    uint256 public currentBrawlId = 1;
    uint256[] public currentEntrants;
    mapping(uint256 => bool) public enteredInCurrentBrawl;
    uint256 public currentPrizePool;
    uint256 public lastBrawlAt;

    uint256 public protocolFeeBalance;
    uint256 public totalBrawlsResolved;
    uint256 public totalMechsScrapped;

    mapping(address => uint256) public pendingWithdrawals;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _deployFee,
        uint256 _entryFee,
        uint256 _brawlInterval,
        uint256 _protocolRakeBps,
        uint32 _initialArmor,
        uint32 _minArmor,
        uint256 _maxEntrantsPerBrawl
    ) {
        require(_brawlInterval > 0, "MechBrawl: brawlInterval=0");
        require(_protocolRakeBps <= 2000, "MechBrawl: rake > 20%");
        require(_initialArmor > _minArmor, "MechBrawl: armor ordering");
        require(_maxEntrantsPerBrawl >= 2, "MechBrawl: maxEntrants < 2");
        require(_maxEntrantsPerBrawl <= 16, "MechBrawl: maxEntrants > 16");

        deployFee = _deployFee;
        entryFee = _entryFee;
        brawlInterval = _brawlInterval;
        protocolRakeBps = _protocolRakeBps;
        initialArmor = _initialArmor;
        minArmor = _minArmor;
        maxEntrantsPerBrawl = _maxEntrantsPerBrawl;
        lastBrawlAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Deploy a new mech at initialArmor.
    function deployMech() external payable returns (uint256 mechId) {
        require(msg.value >= deployFee, "MechBrawl: insufficient deploy fee");

        mechId = nextMechId++;
        _mechs[mechId] = Mech({
            owner: _msgSender(),
            armor: initialArmor,
            victories: 0,
            brawls: 0
        });
        protocolFeeBalance += deployFee;

        uint256 overpayment = msg.value - deployFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "MechBrawl: refund failed");
        }

        emit MechDeployed(mechId, _msgSender(), initialArmor);
    }

    /// @notice Enter a mech in the current brawl.
    function joinBrawl(uint256 mechId) external payable {
        require(msg.value >= entryFee, "MechBrawl: insufficient entry fee");
        Mech storage m = _mechs[mechId];
        require(m.owner == _msgSender(), "MechBrawl: not owner");
        require(m.armor >= minArmor, "MechBrawl: mech scrapped");
        require(
            !enteredInCurrentBrawl[mechId],
            "MechBrawl: already entered"
        );
        require(
            currentEntrants.length < maxEntrantsPerBrawl,
            "MechBrawl: brawl full"
        );

        currentEntrants.push(mechId);
        enteredInCurrentBrawl[mechId] = true;
        currentPrizePool += entryFee;

        uint256 overpayment = msg.value - entryFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "MechBrawl: refund failed");
        }

        emit MechJoined(currentBrawlId, mechId, _msgSender());
    }

    /// @notice Pull-payment winnings claim.
    function claimWinnings() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "MechBrawl: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "MechBrawl: withdraw failed");
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
            (block.timestamp >= lastBrawlAt + brawlInterval) &&
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
            block.timestamp >= lastBrawlAt + brawlInterval,
            "MechBrawl: too soon"
        );
        require(loopID == _loopID, "MechBrawl: stale loop id");
        require(
            currentEntrants.length >= 2,
            "MechBrawl: not enough entrants"
        );

        // ---- Pick winner weighted by armor ----
        uint256 totalArmor = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalArmor += uint256(_mechs[currentEntrants[i]].armor);
        }
        uint256 r = uint256(randomness);
        uint256 winningWeight = r % totalArmor;

        uint256 winnerId;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += uint256(_mechs[currentEntrants[i]].armor);
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
        Mech storage winner = _mechs[winnerId];
        pendingWithdrawals[winner.owner] += prize;
        winner.victories++;

        emit BrawlResolved(
            currentBrawlId,
            winnerId,
            winner.owner,
            prize,
            protocolCut,
            randomness
        );

        // ---- Apply hull damage to all entrants ----
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Mech storage m = _mechs[entrantId];
            m.brawls++;

            uint256 damageRoll = uint256(
                keccak256(abi.encodePacked(randomness, entrantId, "damage"))
            );
            uint32 damageRange = DAMAGE_MAX - DAMAGE_MIN + 1;
            uint32 damageAmount = uint32(DAMAGE_MIN + (damageRoll % damageRange));

            uint32 oldArmor = m.armor;
            uint32 newArmor;
            if (m.armor > damageAmount + minArmor) {
                newArmor = m.armor - damageAmount;
            } else {
                newArmor = minArmor;
                totalMechsScrapped++;
            }
            m.armor = newArmor;
            emit HullDamaged(currentBrawlId, entrantId, oldArmor, newArmor);

            enteredInCurrentBrawl[entrantId] = false;
        }

        // ---- Advance state ----
        lastBrawlAt = block.timestamp;
        totalBrawlsResolved++;
        currentBrawlId++;
        delete currentEntrants;
        currentPrizePool = 0;
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getMech(uint256 mechId) external view returns (Mech memory) {
        return _mechs[mechId];
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
        require(to != address(0), "MechBrawl: zero address");
        require(amount <= protocolFeeBalance, "MechBrawl: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "MechBrawl: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
