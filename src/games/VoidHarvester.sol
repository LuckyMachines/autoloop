// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title VoidHarvester (Deep Anomaly)
 * @author LuckyMachines LLC
 * @notice A persistent deep-space loop where probe missions resolve autonomously on an
 *         unchangeable schedule. Mission fees pool into a prize pot, VRF picks
 *         a winner weighted by probe structural integrity, and all probes lose
 *         integrity each mission.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Two independent reasons:
 *
 *      1. TIMING AS ATTACK SURFACE. If any entrant could trigger the mission
 *         themselves they could pick the block in which the VRF reveal
 *         happens. Even though ECVRF is unpredictable given a fixed seed,
 *         the entrant can CHOOSE whether to actually submit based on their
 *         private anticipation of the outcome — a variant of the front-run
 *         problem. A neutral scheduler eliminates this choice.
 *
 *      2. NEGATIVE-EV FREE-RIDER. Every probe loses integrity each mission.
 *         For most entrants the expected value is negative (only one wins the
 *         pot, everyone pays entry + loses integrity). The rational move is to
 *         let SOMEONE ELSE trigger the mission so you pay the gas only if you
 *         win. Everyone reasons identically, so nobody triggers. A paid
 *         keeper is the only neutral party whose incentives are aligned
 *         with actually running the loop.
 *
 *      Self-incentivized triggering fails on both counts. AutoLoop is the
 *      only way this game can run fairly and continuously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - probeFee on every new probe                  → protocolFeeBalance
 *      - protocolRakeBps on every mission pot          → protocolFeeBalance
 *      - Non-custodial winnings (pull-payment)         → player mapping
 */
contract VoidHarvester is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event ProbeDeployed(
        uint256 indexed probeId,
        address indexed owner,
        uint32 initialIntegrity
    );
    event ProbeLaunched(
        uint256 indexed missionId,
        uint256 indexed probeId,
        address indexed owner
    );
    event MissionResolved(
        uint256 indexed missionId,
        uint256 indexed winningProbeId,
        address indexed winner,
        uint256 prize,
        uint256 protocolFee,
        bytes32 randomness
    );
    event IntegrityLost(
        uint256 indexed missionId,
        uint256 indexed probeId,
        uint32 oldIntegrity,
        uint32 newIntegrity
    );
    event WinningsClaimed(address indexed to, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable probeFee;
    uint256 public immutable missionFee;
    uint256 public immutable missionInterval;
    uint256 public immutable protocolRakeBps;

    uint32 public immutable initialIntegrity;
    uint32 public immutable minIntegrity;

    uint256 public immutable maxProbesPerMission;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint32 public constant DECAY_MIN = 5;
    uint32 public constant DECAY_MAX = 20;

    // ===============================================================
    //  State
    // ===============================================================

    struct Probe {
        address owner;
        uint32 integrity;
        uint32 victories;
        uint32 missions;
    }

    mapping(uint256 => Probe) internal _probes;
    uint256 public nextProbeId = 1;

    uint256 public currentMissionId = 1;
    uint256[] public currentEntrants;
    mapping(uint256 => bool) public enteredInCurrentMission;
    uint256 public currentPrizePool;
    uint256 public lastMissionAt;

    uint256 public protocolFeeBalance;
    uint256 public totalMissionsResolved;
    uint256 public totalProbesDecommissioned;

    mapping(address => uint256) public pendingWithdrawals;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _probeFee,
        uint256 _missionFee,
        uint256 _missionInterval,
        uint256 _protocolRakeBps,
        uint32 _initialIntegrity,
        uint32 _minIntegrity,
        uint256 _maxProbesPerMission
    ) {
        require(_missionInterval > 0, "VoidHarvester: missionInterval=0");
        require(_protocolRakeBps <= 2000, "VoidHarvester: rake > 20%");
        require(_initialIntegrity > _minIntegrity, "VoidHarvester: integrity ordering");
        require(_maxProbesPerMission >= 2, "VoidHarvester: maxProbes < 2");
        require(_maxProbesPerMission <= 16, "VoidHarvester: maxProbes > 16");

        probeFee = _probeFee;
        missionFee = _missionFee;
        missionInterval = _missionInterval;
        protocolRakeBps = _protocolRakeBps;
        initialIntegrity = _initialIntegrity;
        minIntegrity = _minIntegrity;
        maxProbesPerMission = _maxProbesPerMission;
        lastMissionAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Deploy a new probe at initialIntegrity.
    function deployProbe() external payable returns (uint256 probeId) {
        require(msg.value >= probeFee, "VoidHarvester: insufficient probe fee");

        probeId = nextProbeId++;
        _probes[probeId] = Probe({
            owner: _msgSender(),
            integrity: initialIntegrity,
            victories: 0,
            missions: 0
        });
        protocolFeeBalance += probeFee;

        uint256 overpayment = msg.value - probeFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "VoidHarvester: refund failed");
        }

        emit ProbeDeployed(probeId, _msgSender(), initialIntegrity);
    }

    /// @notice Launch a probe into the current mission.
    function launchMission(uint256 probeId) external payable {
        require(msg.value >= missionFee, "VoidHarvester: insufficient mission fee");
        Probe storage p = _probes[probeId];
        require(p.owner == _msgSender(), "VoidHarvester: not owner");
        require(p.integrity >= minIntegrity, "VoidHarvester: probe decommissioned");
        require(
            !enteredInCurrentMission[probeId],
            "VoidHarvester: already launched"
        );
        require(
            currentEntrants.length < maxProbesPerMission,
            "VoidHarvester: mission full"
        );

        currentEntrants.push(probeId);
        enteredInCurrentMission[probeId] = true;
        currentPrizePool += missionFee;

        uint256 overpayment = msg.value - missionFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "VoidHarvester: refund failed");
        }

        emit ProbeLaunched(currentMissionId, probeId, _msgSender());
    }

    /// @notice Pull-payment winnings claim.
    function claimWinnings() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "VoidHarvester: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "VoidHarvester: withdraw failed");
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
            (block.timestamp >= lastMissionAt + missionInterval) &&
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
            block.timestamp >= lastMissionAt + missionInterval,
            "VoidHarvester: too soon"
        );
        require(loopID == _loopID, "VoidHarvester: stale loop id");
        require(
            currentEntrants.length >= 2,
            "VoidHarvester: not enough probes"
        );

        // ---- Pick winner weighted by integrity ----
        uint256 totalIntegrity = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalIntegrity += uint256(_probes[currentEntrants[i]].integrity);
        }
        uint256 r = uint256(randomness);
        uint256 winningWeight = r % totalIntegrity;

        uint256 winnerId;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += uint256(_probes[currentEntrants[i]].integrity);
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
        Probe storage winner = _probes[winnerId];
        pendingWithdrawals[winner.owner] += prize;
        winner.victories++;

        emit MissionResolved(
            currentMissionId,
            winnerId,
            winner.owner,
            prize,
            protocolCut,
            randomness
        );

        // ---- Apply integrity decay to all probes ----
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Probe storage p = _probes[entrantId];
            p.missions++;

            uint256 decayRoll = uint256(
                keccak256(abi.encodePacked(randomness, entrantId, "decay"))
            );
            uint32 decayRange = DECAY_MAX - DECAY_MIN + 1;
            uint32 decayAmount = uint32(DECAY_MIN + (decayRoll % decayRange));

            uint32 oldIntegrity = p.integrity;
            uint32 newIntegrity;
            if (p.integrity > decayAmount + minIntegrity) {
                newIntegrity = p.integrity - decayAmount;
            } else {
                newIntegrity = minIntegrity;
                totalProbesDecommissioned++;
            }
            p.integrity = newIntegrity;
            emit IntegrityLost(currentMissionId, entrantId, oldIntegrity, newIntegrity);

            enteredInCurrentMission[entrantId] = false;
        }

        // ---- Advance state ----
        lastMissionAt = block.timestamp;
        totalMissionsResolved++;
        currentMissionId++;
        delete currentEntrants;
        currentPrizePool = 0;
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getProbe(uint256 probeId) external view returns (Probe memory) {
        return _probes[probeId];
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
        require(to != address(0), "VoidHarvester: zero address");
        require(amount <= protocolFeeBalance, "VoidHarvester: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "VoidHarvester: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
