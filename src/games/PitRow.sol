// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title PitRow (aka Decay Tower)
 * @author LuckyMachines LLC
 * @notice A persistent on-chain tower where each floor holds a race car NFT
 *         that takes catastrophic damage on autonomous VRF ticks and decays
 *         passively between repairs.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      The defining property of PitRow is that every tick has a chance of
 *      damaging a random floor via VRF. A rational floor owner will NEVER
 *      call `progressLoop()` themselves — because the VRF output could pick
 *      their own floor. Every tick is a strict negative expectation for the
 *      player population as a whole: someone loses health.
 *
 *      Self-incentivized triggering, which is the basis of Chainlink's
 *      "users will call it for you" argument, fails here. The only party
 *      whose incentives align with running the loop is a neutral keeper
 *      that gets paid gas + fees. That keeper is AutoLoop.
 *
 *      This makes PitRow the cleanest possible demonstration of why
 *      AutoLoop's paid-keeper model is structurally necessary for a class
 *      of games where the loop imposes costs on every participant.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - `baseMintFee`, scaling with floor number → `protocolFeeBalance`
 *      - `repairFee` on each repair            → `protocolFeeBalance`
 *      - `insurancePremiumBps` on opt-in insured mints → `insurancePool`
 *      - Admin withdraws `protocolFeeBalance` via `withdrawProtocolFees`
 *
 * @dev GAME LOOP
 *      - `shouldProgressLoop()` returns true every `tickInterval` seconds
 *        as long as at least one active floor exists.
 *      - `progressLoop(data)` verifies the VRF proof, picks one active floor
 *        uniformly at random, and applies catastrophic damage in the range
 *        [DAMAGE_MIN, DAMAGE_MAX] basis points of `maxHealth`.
 *      - If effective health reaches zero, the floor collapses and is
 *        removed from the active list. Insured owners can claim a salvage
 *        payout from the insurance pool via `salvage()`.
 *      - Passive decay accrues continuously based on wall-clock time since
 *        the floor's last repair. It requires no on-chain work.
 */
contract PitRow is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event FloorMinted(
        uint256 indexed floorId,
        address indexed owner,
        uint256 mintFee,
        bool insured
    );
    event FloorRepaired(
        uint256 indexed floorId,
        address indexed owner,
        uint256 healthRestored
    );
    event FloorDamaged(
        uint256 indexed floorId,
        uint256 damageApplied,
        uint256 newHealth,
        uint256 indexed loopID,
        bytes32 randomness
    );
    event FloorCollapsed(
        uint256 indexed floorId,
        address indexed owner,
        uint256 indexed loopID
    );
    event FloorSalvaged(
        uint256 indexed floorId,
        address indexed owner,
        uint256 salvageAmount
    );
    event InsurancePoolDonation(address indexed from, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    /// @notice Base fee to mint floor #1 (higher floors cost more)
    uint256 public immutable baseMintFee;

    /// @notice Fixed ETH cost to fully repair a floor
    uint256 public immutable repairFee;

    /// @notice Seconds between VRF damage events
    uint256 public immutable tickInterval;

    /// @notice Maximum health value (in basis points of a full floor)
    uint16 public immutable maxHealth;

    /// @notice Passive decay per hour, in basis points
    uint16 public immutable passiveDecayPerHour;

    /// @notice Opt-in insurance premium, in basis points of mint fee (0-5000)
    uint256 public immutable insurancePremiumBps;

    /// @notice Target salvage payout on collapse, in basis points of the
    ///         collapsed floor's mint fee. Actual payout is capped at the
    ///         current insurance pool balance (shared pool across all
    ///         insured floors), so the contract is never over-committed.
    ///
    /// @dev    Economic notes:
    ///           - Pool grows by `insurancePremiumBps` × mintFee per
    ///             insured mint.
    ///           - Pool shrinks by up to `salvageTargetBps` × mintFee per
    ///             insured collapse.
    ///           - Solvency against full payouts requires expected
    ///             collapse rate × salvageTargetBps ≤ insurancePremiumBps.
    ///             e.g., 10% premium + 50% target = solvent at <20% collapse rate.
    ///           - When the pool is short, later claimants receive
    ///             whatever remains (prorated by arrival order).
    ///           - Admin can top up the pool via `donateToInsurancePool`.
    uint256 public immutable salvageTargetBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Minimum catastrophic damage per tick (basis points)
    uint256 public constant DAMAGE_MIN_BPS = 1500;
    /// @notice Maximum catastrophic damage per tick (basis points)
    uint256 public constant DAMAGE_MAX_BPS = 5000;

    /// @notice Linear mint fee scaling: floor N costs base + base*(N-1)/10
    uint256 public constant MINT_FEE_SCALE_DENOM = 10;

    // ===============================================================
    //  State
    // ===============================================================

    struct Floor {
        address owner; //         slot 0 bytes  0..19
        uint64 mintedAt; //       slot 0 bytes 20..27
        uint32 lastRepairAt; //   slot 0 bytes 28..31
        uint16 damageTaken; //    slot 1
        bool collapsed; //        slot 1
        bool insured; //          slot 1
        bool salvaged; //         slot 1
    }

    mapping(uint256 => Floor) internal _floors;
    uint256 public nextFloorId = 1;

    uint256[] public activeFloorIds;
    mapping(uint256 => uint256) internal _activeIndexPlusOne;

    uint256 public protocolFeeBalance;
    uint256 public insurancePool;

    uint256 public lastTickAt;
    uint256 public totalDamageEvents;
    uint256 public totalCollapses;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _baseMintFee,
        uint256 _repairFee,
        uint256 _tickInterval,
        uint16 _maxHealth,
        uint16 _passiveDecayPerHour,
        uint256 _insurancePremiumBps,
        uint256 _salvageTargetBps
    ) {
        require(_tickInterval > 0, "PitRow: tickInterval=0");
        require(_maxHealth > 0, "PitRow: maxHealth=0");
        require(_insurancePremiumBps <= 5000, "PitRow: insurance premium > 50%");
        require(_salvageTargetBps <= 10000, "PitRow: target > 100%");
        require(_baseMintFee > 0, "PitRow: baseMintFee=0");
        require(_repairFee > 0, "PitRow: repairFee=0");

        baseMintFee = _baseMintFee;
        repairFee = _repairFee;
        tickInterval = _tickInterval;
        maxHealth = _maxHealth;
        passiveDecayPerHour = _passiveDecayPerHour;
        insurancePremiumBps = _insurancePremiumBps;
        salvageTargetBps = _salvageTargetBps;
        lastTickAt = block.timestamp;
    }

    /// @notice Self-register with the AutoLoop registrar (admin only)
    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /**
     * @notice Mint a new floor with a car on it.
     * @param withInsurance If true, pay the insurance premium and receive
     *                      a salvage payout if the floor ever collapses.
     * @return floorId The newly minted floor's id.
     */
    function mintFloor(
        bool withInsurance
    ) external payable returns (uint256 floorId) {
        uint256 currentMintFee = mintFeeFor(nextFloorId);
        uint256 insuranceCost = withInsurance
            ? (currentMintFee * insurancePremiumBps) / BPS_DENOMINATOR
            : 0;
        uint256 totalCost = currentMintFee + insuranceCost;
        require(msg.value >= totalCost, "PitRow: insufficient value");

        floorId = nextFloorId++;
        _floors[floorId] = Floor({
            owner: _msgSender(),
            mintedAt: uint64(block.timestamp),
            lastRepairAt: uint32(block.timestamp),
            damageTaken: 0,
            collapsed: false,
            insured: withInsurance,
            salvaged: false
        });

        _activeIndexPlusOne[floorId] = activeFloorIds.length + 1;
        activeFloorIds.push(floorId);

        protocolFeeBalance += currentMintFee;
        insurancePool += insuranceCost;

        uint256 overpayment = msg.value - totalCost;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "PitRow: refund failed");
        }

        emit FloorMinted(floorId, _msgSender(), currentMintFee, withInsurance);
    }

    /**
     * @notice Pay to fully restore a floor's health.
     * @param floorId The floor to repair.
     */
    function repair(uint256 floorId) external payable {
        Floor storage f = _floors[floorId];
        require(f.owner != address(0), "PitRow: no such floor");
        require(!f.collapsed, "PitRow: floor collapsed");
        require(_msgSender() == f.owner, "PitRow: not owner");
        require(msg.value >= repairFee, "PitRow: insufficient fee");

        uint256 healthBefore = effectiveHealth(floorId);
        f.lastRepairAt = uint32(block.timestamp);
        f.damageTaken = 0;

        protocolFeeBalance += repairFee;

        uint256 overpayment = msg.value - repairFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "PitRow: refund failed");
        }

        emit FloorRepaired(
            floorId,
            _msgSender(),
            uint256(maxHealth) - healthBefore
        );
    }

    /**
     * @notice Claim the salvage payout on a collapsed floor (insured only).
     *         Uninsured collapsed floors can still be called to clear state,
     *         but receive no payout.
     */
    function salvage(uint256 floorId) external {
        Floor storage f = _floors[floorId];
        require(f.owner == _msgSender(), "PitRow: not owner");
        require(f.collapsed, "PitRow: not collapsed");
        require(!f.salvaged, "PitRow: already salvaged");
        f.salvaged = true;

        uint256 salvageAmount = 0;
        if (f.insured) {
            // Shared-pool semantics:
            //   - Target payout = salvageTargetBps × original mint fee
            //   - Capped by the current insurance pool balance
            //   - Pool is cross-subsidized by premiums of floors that
            //     have not (yet) collapsed
            //   - Late claimants against a depleted pool receive whatever
            //     remains
            uint256 originalMintFee = mintFeeFor(floorId);
            uint256 targetPayout = (originalMintFee * salvageTargetBps) /
                BPS_DENOMINATOR;
            salvageAmount = targetPayout > insurancePool
                ? insurancePool
                : targetPayout;
            insurancePool -= salvageAmount;
            if (salvageAmount > 0) {
                (bool sent, ) = _msgSender().call{value: salvageAmount}("");
                require(sent, "PitRow: salvage transfer failed");
            }
        }

        emit FloorSalvaged(floorId, _msgSender(), salvageAmount);
    }

    // ===============================================================
    //  AutoLoop VRF Hooks
    // ===============================================================

    /**
     * @inheritdoc AutoLoopCompatibleInterface
     * @dev Returns ready when the tick interval has elapsed AND at least one
     *      active floor exists. If no floors are active there's nothing to
     *      damage, so the loop idles.
     */
    function shouldProgressLoop()
        external
        view
        override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady =
            (block.timestamp >= lastTickAt + tickInterval) &&
            (activeFloorIds.length > 0);
        progressWithData = abi.encode(_loopID);
    }

    /**
     * @inheritdoc AutoLoopCompatibleInterface
     * @dev Verifies the VRF envelope, extracts randomness, and delegates to
     *      `_progressInternal`. The split exists so tests can inject
     *      randomness without synthesizing valid ECVRF proofs in Solidity.
     */
    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness, bytes memory gameData) = _verifyAndExtractRandomness(
            progressWithData,
            tx.origin
        );
        uint256 loopID = abi.decode(gameData, (uint256));
        _progressInternal(randomness, loopID);
    }

    /**
     * @dev Core tick logic. Visible to tests through a harness subclass.
     */
    function _progressInternal(
        bytes32 randomness,
        uint256 loopID
    ) internal {
        require(
            block.timestamp >= lastTickAt + tickInterval,
            "PitRow: too soon"
        );
        require(loopID == _loopID, "PitRow: stale loop id");
        uint256 activeCount = activeFloorIds.length;
        require(activeCount > 0, "PitRow: no active floors");

        lastTickAt = block.timestamp;
        uint256 r = uint256(randomness);

        uint256 idx = r % activeCount;
        uint256 targetId = activeFloorIds[idx];

        uint256 damageRange = DAMAGE_MAX_BPS - DAMAGE_MIN_BPS + 1;
        uint256 rawDamage = DAMAGE_MIN_BPS + ((r >> 64) % damageRange);

        uint256 currentHealth = effectiveHealth(targetId);
        uint256 damageApplied = rawDamage > currentHealth
            ? currentHealth
            : rawDamage;

        Floor storage f = _floors[targetId];
        // Fold catastrophic damage into accumulated damageTaken.
        // Passive decay since last repair is "locked in" at this moment by
        // resetting lastRepairAt, so f.damageTaken represents the full diff
        // between maxHealth and the new effective health at block.timestamp.
        uint256 lockedDamage = uint256(maxHealth) - currentHealth + damageApplied;
        // uint16 max is 65535; maxHealth is also uint16, so this fits.
        f.damageTaken = uint16(lockedDamage);
        f.lastRepairAt = uint32(block.timestamp);

        uint256 newHealth = currentHealth - damageApplied;
        totalDamageEvents++;
        emit FloorDamaged(targetId, damageApplied, newHealth, _loopID, randomness);

        if (newHealth == 0) {
            f.collapsed = true;
            _removeActive(targetId);
            totalCollapses++;
            emit FloorCollapsed(targetId, f.owner, _loopID);
        }

        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    /**
     * @notice Compute the mint fee for a given floor number.
     * @dev Linear premium: floor N = base + base*(N-1)/10.
     */
    function mintFeeFor(uint256 floorNumber) public view returns (uint256) {
        require(floorNumber > 0, "PitRow: floor=0");
        return
            baseMintFee +
            (baseMintFee * (floorNumber - 1)) /
            MINT_FEE_SCALE_DENOM;
    }

    /**
     * @notice Current effective health of a floor, including passive decay.
     *         Returns 0 for collapsed or non-existent floors.
     */
    function effectiveHealth(
        uint256 floorId
    ) public view returns (uint256) {
        Floor memory f = _floors[floorId];
        if (f.owner == address(0) || f.collapsed) return 0;

        uint256 elapsed = block.timestamp - uint256(f.lastRepairAt);
        uint256 passiveDecay = (uint256(passiveDecayPerHour) * elapsed) / 3600;

        uint256 totalDamage = uint256(f.damageTaken) + passiveDecay;
        if (totalDamage >= uint256(maxHealth)) return 0;
        return uint256(maxHealth) - totalDamage;
    }

    function getFloor(
        uint256 floorId
    ) external view returns (Floor memory) {
        return _floors[floorId];
    }

    function activeFloorCount() external view returns (uint256) {
        return activeFloorIds.length;
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
        require(to != address(0), "PitRow: zero address");
        require(amount <= protocolFeeBalance, "PitRow: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "PitRow: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    // ===============================================================
    //  Internal
    // ===============================================================

    function _removeActive(uint256 floorId) internal {
        uint256 idxPlusOne = _activeIndexPlusOne[floorId];
        require(idxPlusOne != 0, "PitRow: not active");
        uint256 realIdx = idxPlusOne - 1;
        uint256 lastIdx = activeFloorIds.length - 1;

        if (realIdx != lastIdx) {
            uint256 lastId = activeFloorIds[lastIdx];
            activeFloorIds[realIdx] = lastId;
            _activeIndexPlusOne[lastId] = idxPlusOne;
        }
        activeFloorIds.pop();
        _activeIndexPlusOne[floorId] = 0;
    }

    /// @notice Top up the shared insurance pool. Callable by anyone —
    ///         lets the operator (or anyone feeling generous) subsidize
    ///         the pool for marketing / stress events.
    function donateToInsurancePool() external payable {
        require(msg.value > 0, "PitRow: donation=0");
        insurancePool += msg.value;
        emit InsurancePoolDonation(_msgSender(), msg.value);
    }

    /// @notice Required to receive ETH for salvage payouts.
    receive() external payable {}
}
