// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../AutoLoopVRFCompatible.sol";
import "../AutoLoopRegistrar.sol";

/**
 * @title GrandPrix (Always-On Race)
 * @author LuckyMachines LLC
 * @notice A persistent racing loop where races resolve autonomously on an
 *         unchangeable schedule. Entry fees pool into a prize pot, VRF picks
 *         a winner weighted by car power, and all entrants take wear each race.
 *
 * @dev WHY THIS GAME STRUCTURALLY REQUIRES AUTOLOOP
 *      Two independent reasons:
 *
 *      1. TIMING AS ATTACK SURFACE. If any entrant could trigger the race
 *         themselves they could pick the block in which the VRF reveal
 *         happens. Even though ECVRF is unpredictable given a fixed seed,
 *         the entrant can CHOOSE whether to actually submit based on their
 *         private anticipation of the outcome — a variant of the front-run
 *         problem. A neutral scheduler eliminates this choice.
 *
 *      2. NEGATIVE-EV FREE-RIDER. Every entrant takes wear damage each race.
 *         For most entrants the expected value is negative (only one wins the
 *         pot, everyone pays entry + takes wear). The rational move is to
 *         let SOMEONE ELSE trigger the race so you pay the gas only if you
 *         win. Everyone reasons identically, so nobody triggers. A paid
 *         keeper is the only neutral party whose incentives are aligned
 *         with actually running the loop.
 *
 *      Self-incentivized triggering — the basis of Boris Stanic's critique
 *      against paid-keeper models — fails on both counts. AutoLoop is the
 *      only way this game can run fairly and continuously.
 *
 * @dev REVENUE MODEL FOR LUCKYMACHINES
 *      - carMintFee on every new car             → protocolFeeBalance
 *      - protocolRakeBps on every race pot        → protocolFeeBalance
 *      - Non-custodial winnings (pull-payment)    → player mapping
 */
contract GrandPrix is AutoLoopVRFCompatible {
    // ===============================================================
    //  Events
    // ===============================================================

    event CarMinted(
        uint256 indexed carId,
        address indexed owner,
        uint32 initialPower
    );
    event CarEntered(
        uint256 indexed raceId,
        uint256 indexed carId,
        address indexed owner
    );
    event RaceResolved(
        uint256 indexed raceId,
        uint256 indexed winningCarId,
        address indexed winner,
        uint256 prize,
        uint256 protocolFee,
        bytes32 randomness
    );
    event WearApplied(
        uint256 indexed raceId,
        uint256 indexed carId,
        uint32 oldPower,
        uint32 newPower
    );
    event WinningsClaimed(address indexed to, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    // ===============================================================
    //  Configuration (immutable)
    // ===============================================================

    uint256 public immutable carMintFee;
    uint256 public immutable entryFee;
    uint256 public immutable raceInterval;
    uint256 public immutable protocolRakeBps;

    uint32 public immutable initialPower;
    uint32 public immutable minPower;

    uint256 public immutable maxEntrantsPerRace;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint32 public constant WEAR_MIN = 5;
    uint32 public constant WEAR_MAX = 20;

    // ===============================================================
    //  State
    // ===============================================================

    struct Car {
        address owner;
        uint32 power;
        uint32 wins;
        uint32 races;
    }

    mapping(uint256 => Car) internal _cars;
    uint256 public nextCarId = 1;

    uint256 public currentRaceId = 1;
    uint256[] public currentEntrants;
    mapping(uint256 => bool) public enteredInCurrentRace;
    uint256 public currentPrizePool;
    uint256 public lastRaceAt;

    uint256 public protocolFeeBalance;
    uint256 public totalRacesResolved;
    uint256 public totalCarsBurned;

    mapping(address => uint256) public pendingWithdrawals;

    // ===============================================================
    //  Constructor
    // ===============================================================

    constructor(
        uint256 _carMintFee,
        uint256 _entryFee,
        uint256 _raceInterval,
        uint256 _protocolRakeBps,
        uint32 _initialPower,
        uint32 _minPower,
        uint256 _maxEntrantsPerRace
    ) {
        require(_raceInterval > 0, "GrandPrix: raceInterval=0");
        require(_protocolRakeBps <= 2000, "GrandPrix: rake > 20%");
        require(_initialPower > _minPower, "GrandPrix: power ordering");
        require(_maxEntrantsPerRace >= 2, "GrandPrix: maxEntrants < 2");
        require(_maxEntrantsPerRace <= 16, "GrandPrix: maxEntrants > 16");

        carMintFee = _carMintFee;
        entryFee = _entryFee;
        raceInterval = _raceInterval;
        protocolRakeBps = _protocolRakeBps;
        initialPower = _initialPower;
        minPower = _minPower;
        maxEntrantsPerRace = _maxEntrantsPerRace;
        lastRaceAt = block.timestamp;
    }

    function register(address registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AutoLoopRegistrar(registrar).registerAutoLoop();
    }

    // ===============================================================
    //  Public Actions
    // ===============================================================

    /// @notice Mint a new car at initialPower.
    function mintCar() external payable returns (uint256 carId) {
        require(msg.value >= carMintFee, "GrandPrix: insufficient mint fee");

        carId = nextCarId++;
        _cars[carId] = Car({
            owner: _msgSender(),
            power: initialPower,
            wins: 0,
            races: 0
        });
        protocolFeeBalance += carMintFee;

        uint256 overpayment = msg.value - carMintFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "GrandPrix: refund failed");
        }

        emit CarMinted(carId, _msgSender(), initialPower);
    }

    /// @notice Enter a car in the current race.
    function enterRace(uint256 carId) external payable {
        require(msg.value >= entryFee, "GrandPrix: insufficient entry fee");
        Car storage c = _cars[carId];
        require(c.owner == _msgSender(), "GrandPrix: not owner");
        require(c.power >= minPower, "GrandPrix: car retired");
        require(
            !enteredInCurrentRace[carId],
            "GrandPrix: already entered"
        );
        require(
            currentEntrants.length < maxEntrantsPerRace,
            "GrandPrix: race full"
        );

        currentEntrants.push(carId);
        enteredInCurrentRace[carId] = true;
        currentPrizePool += entryFee;

        uint256 overpayment = msg.value - entryFee;
        if (overpayment > 0) {
            (bool sent, ) = _msgSender().call{value: overpayment}("");
            require(sent, "GrandPrix: refund failed");
        }

        emit CarEntered(currentRaceId, carId, _msgSender());
    }

    /// @notice Pull-payment winnings claim.
    function claimWinnings() external {
        uint256 amount = pendingWithdrawals[_msgSender()];
        require(amount > 0, "GrandPrix: nothing to claim");
        pendingWithdrawals[_msgSender()] = 0;
        (bool sent, ) = _msgSender().call{value: amount}("");
        require(sent, "GrandPrix: withdraw failed");
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
            (block.timestamp >= lastRaceAt + raceInterval) &&
            (currentEntrants.length >= 2);
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

    /**
     * @dev Core race resolution. Exposed to tests via harness.
     */
    function _progressInternal(
        bytes32 randomness,
        uint256 loopID
    ) internal {
        require(
            block.timestamp >= lastRaceAt + raceInterval,
            "GrandPrix: too soon"
        );
        require(loopID == _loopID, "GrandPrix: stale loop id");
        require(
            currentEntrants.length >= 2,
            "GrandPrix: not enough entrants"
        );

        // ---- Pick winner weighted by power ----
        uint256 totalPower = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            totalPower += uint256(_cars[currentEntrants[i]].power);
        }
        uint256 r = uint256(randomness);
        uint256 winningWeight = r % totalPower;

        uint256 winnerId;
        uint256 cumulative = 0;
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            cumulative += uint256(_cars[currentEntrants[i]].power);
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
        Car storage winner = _cars[winnerId];
        pendingWithdrawals[winner.owner] += prize;
        winner.wins++;

        emit RaceResolved(
            currentRaceId,
            winnerId,
            winner.owner,
            prize,
            protocolCut,
            randomness
        );

        // ---- Apply wear to all entrants ----
        for (uint256 i = 0; i < currentEntrants.length; i++) {
            uint256 entrantId = currentEntrants[i];
            Car storage c = _cars[entrantId];
            c.races++;

            uint256 wearRoll = uint256(
                keccak256(abi.encodePacked(randomness, entrantId, "wear"))
            );
            uint32 wearRange = WEAR_MAX - WEAR_MIN + 1;
            uint32 wearAmount = uint32(
                WEAR_MIN + (wearRoll % wearRange)
            );

            uint32 oldPower = c.power;
            uint32 newPower;
            if (c.power > wearAmount + minPower) {
                newPower = c.power - wearAmount;
            } else {
                newPower = minPower;
                totalCarsBurned++;
            }
            c.power = newPower;
            emit WearApplied(currentRaceId, entrantId, oldPower, newPower);

            // Clear entry flag for next race
            enteredInCurrentRace[entrantId] = false;
        }

        // ---- Advance state ----
        lastRaceAt = block.timestamp;
        totalRacesResolved++;
        currentRaceId++;
        delete currentEntrants;
        currentPrizePool = 0;
        ++_loopID;
    }

    // ===============================================================
    //  Views
    // ===============================================================

    function getCar(uint256 carId) external view returns (Car memory) {
        return _cars[carId];
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
        require(to != address(0), "GrandPrix: zero address");
        require(amount <= protocolFeeBalance, "GrandPrix: exceeds balance");
        protocolFeeBalance -= amount;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "GrandPrix: withdraw failed");
        emit ProtocolFeesWithdrawn(to, amount);
    }

    receive() external payable {}
}
