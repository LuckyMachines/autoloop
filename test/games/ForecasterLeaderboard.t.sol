// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/games/KaijuLeague.sol";
import "../../src/games/KaijuOracle.sol";
import "../../src/games/ForecasterLeaderboard.sol";

// ===============================================================
//  League harness
// ===============================================================

contract LeagueForLeaderboard is KaijuLeague {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) KaijuLeague(a, b, c, d, e, f, g) {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }
}

// ===============================================================
//  Test suite
// ===============================================================

contract ForecasterLeaderboardTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    LeagueForLeaderboard public league;
    KaijuOracle public oracle;
    ForecasterLeaderboard public leaderboard;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;

    // League accounts that own the two permanent kaijus k1 and k2
    address public k1Owner;
    address public k2Owner;

    uint256 constant COMMIT_DURATION        = 60;
    uint256 constant REVEAL_DURATION        = 60;
    uint256 constant MIN_STAKE              = 0.001 ether;
    uint256 constant PROTOCOL_RAKE          = 500; // 5%
    uint256 constant KAIJU_FEE              = 0.01 ether;
    uint256 constant ENTRY_FEE              = 0.001 ether;
    uint256 constant CLASH_INTERVAL         = 60;
    uint256 constant DISTRIBUTION_INTERVAL  = 3600; // 1 hour season
    uint256 constant TOP_N                  = 3;
    uint256 constant MAX_ROUNDS_PER_TICK    = 20;

    receive() external payable {}

    function setUp() public {
        proxyAdmin = vm.addr(99);
        alice      = vm.addr(0xA11CE);
        bob        = vm.addr(0xB0B);
        carol      = vm.addr(0xCA20A);
        dave       = vm.addr(0xDA5E);
        k1Owner    = vm.addr(0xBEEF1);
        k2Owner    = vm.addr(0xBEEF2);
        admin      = address(this);

        vm.deal(admin,    1000 ether);
        vm.deal(alice,     100 ether);
        vm.deal(bob,       100 ether);
        vm.deal(carol,     100 ether);
        vm.deal(dave,      100 ether);
        vm.deal(k1Owner,   10 ether);
        vm.deal(k2Owner,   10 ether);

        AutoLoop autoLoopImpl = new AutoLoop();
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl), proxyAdmin,
            abi.encodeWithSignature("initialize(string)", "0.0.1")
        );
        autoLoop = AutoLoop(address(autoLoopProxy));

        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl), proxyAdmin,
            abi.encodeWithSignature("initialize(address)", admin)
        );
        registry = AutoLoopRegistry(address(registryProxy));

        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();
        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl), proxyAdmin,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(autoLoop), address(registry), admin
            )
        );
        registrar = AutoLoopRegistrar(address(registrarProxy));
        registry.setRegistrar(address(registrar));
        autoLoop.setRegistrar(address(registrar));

        league = new LeagueForLeaderboard(
            KAIJU_FEE, ENTRY_FEE, CLASH_INTERVAL, PROTOCOL_RAKE,
            500, 50, 8
        );
        oracle = new KaijuOracle(
            address(league), COMMIT_DURATION, REVEAL_DURATION,
            MIN_STAKE, PROTOCOL_RAKE
        );
        leaderboard = new ForecasterLeaderboard(
            address(oracle), DISTRIBUTION_INTERVAL, TOP_N,
            MAX_ROUNDS_PER_TICK, PROTOCOL_RAKE
        );

        // Pre-mint two permanent kaijus owned by k1Owner and k2Owner
        vm.prank(k1Owner); league.hatchKaiju{value: KAIJU_FEE}(); // kaijuId = 1
        vm.prank(k2Owner); league.hatchKaiju{value: KAIJU_FEE}(); // kaijuId = 2
    }

    // ===============================================================
    //  Section 1 — Initial state
    // ===============================================================

    function test_InitialState() public view {
        assertEq(leaderboard.currentSeason(), 1);
        assertEq(leaderboard.prizePool(), 0);
        assertEq(leaderboard.totalSeasonsCompleted(), 0);
        assertEq(leaderboard.forecasterCount(), 0);
        assertGt(leaderboard.nextDistributionAt(), block.timestamp);
    }

    function test_Immutables() public view {
        assertEq(address(leaderboard.kaijuOracle()), address(oracle));
        assertEq(leaderboard.distributionInterval(), DISTRIBUTION_INTERVAL);
        assertEq(leaderboard.topN(), TOP_N);
        assertEq(leaderboard.maxRoundsPerTick(), MAX_ROUNDS_PER_TICK);
        assertEq(leaderboard.protocolRakeBps(), PROTOCOL_RAKE);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroOracle() public {
        vm.expectRevert("ForecasterLeaderboard: oracle=0");
        new ForecasterLeaderboard(address(0), DISTRIBUTION_INTERVAL, TOP_N, MAX_ROUNDS_PER_TICK, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroInterval() public {
        vm.expectRevert("ForecasterLeaderboard: interval=0");
        new ForecasterLeaderboard(address(oracle), 0, TOP_N, MAX_ROUNDS_PER_TICK, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroTopN() public {
        vm.expectRevert("ForecasterLeaderboard: topN range");
        new ForecasterLeaderboard(address(oracle), DISTRIBUTION_INTERVAL, 0, MAX_ROUNDS_PER_TICK, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsTopNTooHigh() public {
        vm.expectRevert("ForecasterLeaderboard: topN range");
        new ForecasterLeaderboard(address(oracle), DISTRIBUTION_INTERVAL, 11, MAX_ROUNDS_PER_TICK, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroMaxRounds() public {
        vm.expectRevert("ForecasterLeaderboard: maxRounds=0");
        new ForecasterLeaderboard(address(oracle), DISTRIBUTION_INTERVAL, TOP_N, 0, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("ForecasterLeaderboard: rake > 20%");
        new ForecasterLeaderboard(address(oracle), DISTRIBUTION_INTERVAL, TOP_N, MAX_ROUNDS_PER_TICK, 2001);
    }

    // ===============================================================
    //  Section 3 — shouldProgressLoop
    // ===============================================================

    function test_ShouldProgressFalseBeforeInterval() public view {
        (bool ready, ) = leaderboard.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueAfterInterval() public {
        vm.warp(leaderboard.nextDistributionAt());
        (bool ready, ) = leaderboard.shouldProgressLoop();
        assertTrue(ready);
    }

    // ===============================================================
    //  Section 4 — Distribution with no forecasters
    // ===============================================================

    function test_DistributeWithNoPrizePool() public {
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));
        assertEq(leaderboard.currentSeason(), 2);
        assertEq(leaderboard.totalSeasonsCompleted(), 1);
        assertEq(leaderboard.prizePool(), 0);
    }

    function test_DistributeWithPrizePoolButNoForecasters() public {
        leaderboard.fundPrizePool{value: 1 ether}();
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));
        // All goes to protocol
        assertGt(leaderboard.protocolFeeBalance(), 0);
        assertEq(leaderboard.prizePool(), 0);
        assertEq(leaderboard.currentSeason(), 2);
    }

    // ===============================================================
    //  Section 5 — Score recording
    // ===============================================================

    function test_CorrectPredictionRecorded() public {
        leaderboard.fundPrizePool{value: 1 ether}();

        // alice predicts k1 wins (and k1 will win)
        _commitFor(alice, 1, bytes32(uint256(1)));
        _warpToRevealAndReveal(alice, 1, bytes32(uint256(1)));
        _resolveLeagueAndSettle();  // k1 wins

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        ForecasterLeaderboard.ForecasterStats memory s = leaderboard.getStats(alice);
        assertEq(s.lifetimeTotal, 1);
        assertEq(s.lifetimeCorrect, 1);
    }

    function test_WrongPredictionRecorded() public {
        leaderboard.fundPrizePool{value: 1 ether}();

        // alice predicts k2 wins, but k1 wins
        _commitFor(alice, 2, bytes32(uint256(1)));
        _warpToRevealAndReveal(alice, 2, bytes32(uint256(1)));
        _resolveLeagueAndSettle();

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        ForecasterLeaderboard.ForecasterStats memory s = leaderboard.getStats(alice);
        assertEq(s.lifetimeTotal, 1);
        assertEq(s.lifetimeCorrect, 0);
    }

    function test_UnrevealedNotCounted() public {
        leaderboard.fundPrizePool{value: 1 ether}();

        // alice commits but never reveals
        _commitFor(alice, 1, bytes32(uint256(1)));
        // Warp to reveal phase but alice doesn't reveal
        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        vm.warp(r.commitEndAt + 1);
        _resolveLeagueAndSettle();

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        ForecasterLeaderboard.ForecasterStats memory s = leaderboard.getStats(alice);
        assertEq(s.lifetimeTotal, 0); // not counted — didn't reveal
    }

    function test_MultipleForecasterScores() public {
        leaderboard.fundPrizePool{value: 1 ether}();

        _commitFor(alice, 1, bytes32(uint256(1)));
        _commitFor(bob,   2, bytes32(uint256(2)));
        _commitFor(carol, 1, bytes32(uint256(3)));

        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        vm.warp(r.commitEndAt + 1);
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(1)));
        vm.prank(bob);   oracle.reveal(2, bytes32(uint256(2)));
        vm.prank(carol); oracle.reveal(1, bytes32(uint256(3)));

        _resolveLeagueAndSettle(); // k1 wins → alice + carol correct

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        assertEq(leaderboard.getStats(alice).lifetimeCorrect, 1);
        assertEq(leaderboard.getStats(bob).lifetimeCorrect, 0);
        assertEq(leaderboard.getStats(carol).lifetimeCorrect, 1);
        assertEq(leaderboard.forecasterCount(), 3);
    }

    // ===============================================================
    //  Section 6 — Prize distribution
    // ===============================================================

    function test_CorrectForecasterGetsPrize() public {
        uint256 prize = 1 ether;
        leaderboard.fundPrizePool{value: prize}();

        _commitFor(alice, 1, bytes32(uint256(1)));
        _commitFor(bob,   2, bytes32(uint256(2)));
        _warpToRevealAndReveal(alice, 1, bytes32(uint256(1)));
        _warpToRevealAndReveal(bob,   2, bytes32(uint256(2)));
        _resolveLeagueAndSettle(); // k1 wins → alice correct, bob wrong

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        uint256 rake = (prize * PROTOCOL_RAKE) / 10_000;
        uint256 distributable = prize - rake;
        // alice is the only correct forecaster → gets all distributable
        assertEq(leaderboard.seasonPrizes(1, alice), distributable);
        assertEq(leaderboard.seasonPrizes(1, bob), 0);

        uint256 before = alice.balance;
        vm.prank(alice); leaderboard.claimSeasonPrize(1);
        assertEq(alice.balance - before, distributable);
    }

    function test_TiedForecastersSharePrize() public {
        uint256 prize = 1 ether;
        leaderboard.fundPrizePool{value: prize}();

        _commitFor(alice, 1, bytes32(uint256(1)));
        _commitFor(bob,   1, bytes32(uint256(2)));

        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        vm.warp(r.commitEndAt + 1);
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(1)));
        vm.prank(bob);   oracle.reveal(1, bytes32(uint256(2)));

        _resolveLeagueAndSettle(); // k1 wins → both correct

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        // Both in top 3, equal share
        assertGt(leaderboard.seasonPrizes(1, alice), 0);
        assertGt(leaderboard.seasonPrizes(1, bob), 0);
        assertEq(leaderboard.seasonPrizes(1, alice), leaderboard.seasonPrizes(1, bob));
    }

    function test_SeasonResetsAfterDistribution() public {
        leaderboard.fundPrizePool{value: 1 ether}();
        _commitFor(alice, 1, bytes32(uint256(1)));
        _warpToRevealAndReveal(alice, 1, bytes32(uint256(1)));
        _resolveLeagueAndSettle();

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        ForecasterLeaderboard.ForecasterStats memory s = leaderboard.getStats(alice);
        assertEq(s.seasonCorrect, 0);
        assertEq(s.seasonTotal, 0);
        assertEq(s.lifetimeCorrect, 1);
        assertEq(s.lifetimeTotal, 1);
    }

    function test_MultipleSeasons() public {
        // Season 1
        leaderboard.fundPrizePool{value: 1 ether}();
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));
        assertEq(leaderboard.currentSeason(), 2);

        // Season 2
        leaderboard.fundPrizePool{value: 0.5 ether}();
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(2)));
        assertEq(leaderboard.currentSeason(), 3);
        assertEq(leaderboard.totalSeasonsCompleted(), 2);
    }

    function test_LifetimeStatsAccumulateAcrossSeasons() public {
        leaderboard.fundPrizePool{value: 1 ether}();

        // Season 1: alice correct
        _commitFor(alice, 1, bytes32(uint256(1)));
        _warpToRevealAndReveal(alice, 1, bytes32(uint256(1)));
        _resolveLeagueAndSettle();

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        assertEq(leaderboard.getStats(alice).lifetimeCorrect, 1);
        assertEq(leaderboard.getStats(alice).seasonCorrect,   0); // reset

        // Season 2: alice predicts wrong (but we just do distribution with no new rounds)
        leaderboard.fundPrizePool{value: 0.5 ether}();
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(2)));

        // Lifetime should still be 1 (no new rounds processed)
        assertEq(leaderboard.getStats(alice).lifetimeCorrect, 1);
    }

    // ===============================================================
    //  Section 7 — Claim mechanics
    // ===============================================================

    function test_ClaimRejectsNoPrize() public {
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        vm.prank(bob);
        vm.expectRevert("ForecasterLeaderboard: no prize");
        leaderboard.claimSeasonPrize(1);
    }

    function test_ClaimRejectsDouble() public {
        leaderboard.fundPrizePool{value: 1 ether}();
        _commitFor(alice, 1, bytes32(uint256(1)));
        _warpToRevealAndReveal(alice, 1, bytes32(uint256(1)));
        _resolveLeagueAndSettle();

        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        vm.prank(alice); leaderboard.claimSeasonPrize(1);
        vm.prank(alice);
        vm.expectRevert("ForecasterLeaderboard: already claimed");
        leaderboard.claimSeasonPrize(1);
    }

    // ===============================================================
    //  Section 8 — Fund prize pool
    // ===============================================================

    function test_FundPrizePool() public {
        leaderboard.fundPrizePool{value: 0.5 ether}();
        assertEq(leaderboard.prizePool(), 0.5 ether);
    }

    function test_FundPrizePoolViaReceive() public {
        (bool ok, ) = address(leaderboard).call{value: 0.3 ether}("");
        require(ok);
        assertEq(leaderboard.prizePool(), 0.3 ether);
    }

    function test_FundRejectsZero() public {
        vm.expectRevert("ForecasterLeaderboard: amount=0");
        leaderboard.fundPrizePool{value: 0}();
    }

    // ===============================================================
    //  Section 9 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        leaderboard.fundPrizePool{value: 1 ether}();
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        uint256 fee = leaderboard.protocolFeeBalance();
        assertGt(fee, 0);
        uint256 before = admin.balance;
        leaderboard.withdrawProtocolFees(admin, fee);
        assertEq(admin.balance - before, fee);
    }

    function test_WithdrawRejectsNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        leaderboard.withdrawProtocolFees(alice, 0);
    }

    function test_WithdrawRejectsZeroAddress() public {
        vm.expectRevert("ForecasterLeaderboard: zero address");
        leaderboard.withdrawProtocolFees(address(0), 0);
    }

    // ===============================================================
    //  Section 10 — Stale season rejection
    // ===============================================================

    function test_ProgressRejectsStateSeason() public {
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        vm.warp(leaderboard.nextDistributionAt());
        vm.expectRevert("ForecasterLeaderboard: stale season");
        leaderboard.progressLoop(abi.encode(uint256(1)));
    }

    function test_ProgressRejectsTooSoon() public {
        vm.expectRevert("ForecasterLeaderboard: too soon");
        leaderboard.progressLoop(abi.encode(uint256(1)));
    }

    // ===============================================================
    //  Section 11 — Fuzz
    // ===============================================================

    function testFuzz_PotFullyAllocated(uint256 fundAmount) public {
        fundAmount = bound(fundAmount, 0.01 ether, 10 ether);
        leaderboard.fundPrizePool{value: fundAmount}();

        _commitFor(alice, 1, bytes32(uint256(1)));
        _warpToRevealAndReveal(alice, 1, bytes32(uint256(1)));
        _resolveLeagueAndSettle();

        uint256 protocolBefore = leaderboard.protocolFeeBalance();
        vm.warp(leaderboard.nextDistributionAt());
        leaderboard.progressLoop(abi.encode(uint256(1)));

        uint256 protocolGained = leaderboard.protocolFeeBalance() - protocolBefore;
        uint256 alicePrize = leaderboard.seasonPrizes(1, alice);
        assertEq(protocolGained + alicePrize, fundAmount);
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _commitFor(address player, uint256 kaijuId, bytes32 salt) internal {
        bytes32 c = keccak256(abi.encode(kaijuId, salt, player));
        vm.prank(player);
        oracle.commit{value: MIN_STAKE}(c);
    }

    /// @dev Warp to reveal phase (if not already there) and reveal for one player.
    function _warpToRevealAndReveal(address player, uint256 kaijuId, bytes32 salt) internal {
        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        if (block.timestamp < r.commitEndAt) {
            vm.warp(r.commitEndAt + 1);
        }
        vm.prank(player);
        oracle.reveal(kaijuId, salt);
    }

    /// @dev Warp past all deadlines, enter k1+k2 into league (if not already),
    ///      resolve league (k1 wins, rand=0), and settle oracle.
    function _resolveLeagueAndSettle() internal {
        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        uint256 leagueDeadline = league.lastClashAt() + CLASH_INTERVAL;
        uint256 t = r.revealEndAt > leagueDeadline ? r.revealEndAt : leagueDeadline;
        vm.warp(t);

        // Enter k1 and k2 if not already in
        if (!league.enteredInCurrentClash(1)) {
            vm.prank(k1Owner); league.enterClash{value: ENTRY_FEE}(1);
        }
        if (!league.enteredInCurrentClash(2)) {
            vm.prank(k2Owner); league.enterClash{value: ENTRY_FEE}(2);
        }

        league.tickForTest(bytes32(uint256(0))); // k1 wins
        oracle.progressLoop(abi.encode(oracle.currentRoundId()));
    }
}
