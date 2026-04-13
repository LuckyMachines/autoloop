// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/KaijuLeague.sol";
import "../../src/games/KaijuOracle.sol";

// ===============================================================
//  League harness — exposes _progressInternal for deterministic tests
// ===============================================================

contract LeagueForOracle is KaijuLeague {
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

contract KaijuOracleTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    LeagueForOracle public league;
    KaijuOracle public oracle;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant COMMIT_DURATION = 120;
    uint256 constant REVEAL_DURATION = 120;
    uint256 constant MIN_STAKE       = 0.001 ether;
    uint256 constant PROTOCOL_RAKE   = 500; // 5%
    uint256 constant KAIJU_FEE       = 0.01 ether;
    uint256 constant ENTRY_FEE       = 0.001 ether;
    uint256 constant CLASH_INTERVAL  = 60;

    receive() external payable {}

    function setUp() public {
        proxyAdmin  = vm.addr(99);
        alice       = vm.addr(0xA11CE);
        bob         = vm.addr(0xB0B);
        carol       = vm.addr(0xCA20A);
        dave        = vm.addr(0xDA5E);
        controller1 = vm.addr(0xC0DE);
        admin       = address(this);

        vm.deal(admin,       1000 ether);
        vm.deal(alice,        100 ether);
        vm.deal(bob,          100 ether);
        vm.deal(carol,        100 ether);
        vm.deal(dave,         100 ether);
        vm.deal(controller1,  100 ether);

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

        league = new LeagueForOracle(
            KAIJU_FEE, ENTRY_FEE, CLASH_INTERVAL, PROTOCOL_RAKE,
            500, 50, 8
        );
        registrar.registerAutoLoopFor(address(league), 2_000_000);
        registrar.deposit{value: 10 ether}(address(league));

        oracle = new KaijuOracle(
            address(league),
            COMMIT_DURATION,
            REVEAL_DURATION,
            MIN_STAKE,
            PROTOCOL_RAKE
        );
        registrar.registerAutoLoopFor(address(oracle), 2_000_000);
        registrar.deposit{value: 10 ether}(address(oracle));

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();
    }

    // ===============================================================
    //  Section 1 — Initial state
    // ===============================================================

    function test_InitialState() public view {
        assertEq(oracle.currentRoundId(), 1);
        assertEq(oracle.protocolFeeBalance(), 0);
        KaijuOracle.Round memory r = oracle.getRound(1);
        assertFalse(r.settled);
        assertEq(r.totalPot, 0);
        assertEq(r.targetClashId, league.currentClashId());
    }

    function test_Immutables() public view {
        assertEq(oracle.commitDuration(), COMMIT_DURATION);
        assertEq(oracle.revealDuration(), REVEAL_DURATION);
        assertEq(oracle.minStake(), MIN_STAKE);
        assertEq(oracle.protocolRakeBps(), PROTOCOL_RAKE);
        assertEq(address(oracle.kaijuLeague()), address(league));
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroLeague() public {
        vm.expectRevert("KaijuOracle: league=0");
        new KaijuOracle(address(0), COMMIT_DURATION, REVEAL_DURATION, MIN_STAKE, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroCommit() public {
        vm.expectRevert("KaijuOracle: commit=0");
        new KaijuOracle(address(league), 0, REVEAL_DURATION, MIN_STAKE, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroReveal() public {
        vm.expectRevert("KaijuOracle: reveal=0");
        new KaijuOracle(address(league), COMMIT_DURATION, 0, MIN_STAKE, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroStake() public {
        vm.expectRevert("KaijuOracle: stake=0");
        new KaijuOracle(address(league), COMMIT_DURATION, REVEAL_DURATION, 0, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("KaijuOracle: rake > 20%");
        new KaijuOracle(address(league), COMMIT_DURATION, REVEAL_DURATION, MIN_STAKE, 2001);
    }

    // ===============================================================
    //  Section 3 — Commit phase
    // ===============================================================

    function test_Commit() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(42)));
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);

        assertEq(oracle.commits(1, alice), c);
        assertEq(oracle.stakes(1, alice), MIN_STAKE);
        assertEq(oracle.revealedKaijus(1, alice), oracle.KAIJU_UNREVEALED());

        KaijuOracle.Round memory r = oracle.getRound(1);
        assertEq(r.totalPot, MIN_STAKE);
    }

    function test_CommitTracksParticipant() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(42)));
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);
        assertEq(oracle.getRoundParticipantCount(1), 1);
        assertEq(oracle.getRoundParticipant(1, 0), alice);
    }

    function test_CommitMultipleParticipants() public {
        _commitFor(alice, 1, bytes32(uint256(1)), MIN_STAKE);
        _commitFor(bob,   2, bytes32(uint256(2)), MIN_STAKE);
        _commitFor(carol, 1, bytes32(uint256(3)), MIN_STAKE);
        assertEq(oracle.getRoundParticipantCount(1), 3);
    }

    function test_CommitRejectsLowStake() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: stake too low");
        oracle.commit{value: MIN_STAKE - 1}(c);
    }

    function test_CommitRejectsDouble() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: already committed");
        oracle.commit{value: MIN_STAKE}(c);
    }

    function test_CommitRejectsEmpty() public {
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: empty commit");
        oracle.commit{value: MIN_STAKE}(bytes32(0));
    }

    function test_CommitRejectsAfterCommitPhase() public {
        KaijuOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.commitEndAt);
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: commit phase over");
        oracle.commit{value: MIN_STAKE}(c);
    }

    function test_CommitEmitsEvent() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(42)));
        vm.expectEmit(true, true, false, true, address(oracle));
        emit KaijuOracle.Committed(1, alice, MIN_STAKE, c);
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);
    }

    // ===============================================================
    //  Section 4 — Reveal phase
    // ===============================================================

    function test_Reveal() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        oracle.reveal(1, bytes32(uint256(42)));

        assertEq(oracle.revealedKaijus(1, alice), 1);
        assertEq(oracle.revealedTotalPerKaiju(1, 1), MIN_STAKE);
        assertEq(oracle.revealedCountPerKaiju(1, 1), 1);
    }

    function test_RevealRejectsBeforeCommitPhaseEnd() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: still commit phase");
        oracle.reveal(1, bytes32(uint256(42)));
    }

    function test_RevealRejectsAfterRevealPhase() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        KaijuOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.revealEndAt);
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: reveal phase over");
        oracle.reveal(1, bytes32(uint256(42)));
    }

    function test_RevealRejectsBadSalt() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: bad reveal");
        oracle.reveal(1, bytes32(uint256(99)));
    }

    function test_RevealRejectsBadKaijuId() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: bad reveal");
        oracle.reveal(2, bytes32(uint256(42)));
    }

    function test_RevealRejectsDouble() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: already revealed");
        oracle.reveal(1, bytes32(uint256(42)));
    }

    function test_RevealRejectsZeroKaiju() public {
        bytes32 c = keccak256(abi.encode(uint256(0), bytes32(uint256(1)), alice));
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: invalid kaiju");
        oracle.reveal(0, bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 5 — Settlement & payout (cross-contract integration)
    // ===============================================================

    function test_SettleWithWinners() public {
        // alice and bob predict kaiju 1; carol predicts kaiju 2
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   1, bytes32(uint256(43)), MIN_STAKE);
        _commitFor(carol, 2, bytes32(uint256(44)), MIN_STAKE);

        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(bob);   oracle.reveal(1, bytes32(uint256(43)));
        vm.prank(carol); oracle.reveal(2, bytes32(uint256(44)));

        // Enter two kaiju into the league clash
        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}(); // k1
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}(); // k2
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);

        // Resolve league. rand=0 → winningWeight=0, first entrant (k1) wins.
        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0)));
        assertEq(league.clashWinners(1), 1); // clash 1, winner = kaiju 1

        // Settle oracle
        oracle.progressLoop(abi.encode(uint256(1)));

        KaijuOracle.Round memory settled = oracle.getRound(1);
        assertTrue(settled.settled);
        assertEq(settled.winningKaijuId, 1);
        assertEq(settled.winningTotalStake, MIN_STAKE * 2); // alice + bob

        uint256 totalPot = MIN_STAKE * 3;
        uint256 rake = (totalPot * PROTOCOL_RAKE) / 10_000;
        uint256 share = (totalPot - rake) / 2;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice); oracle.claimWinnings(1);
        assertEq(alice.balance - aliceBefore, share);

        uint256 bobBefore = bob.balance;
        vm.prank(bob); oracle.claimWinnings(1);
        assertEq(bob.balance - bobBefore, share);

        assertEq(oracle.protocolFeeBalance(), rake);
    }

    function test_SettleWithNoWinners() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(2, bytes32(uint256(42)));

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}(); // k1
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}(); // k2
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0))); // k1 wins

        oracle.progressLoop(abi.encode(uint256(1)));

        KaijuOracle.Round memory settled = oracle.getRound(1);
        assertEq(settled.winningKaijuId, 1); // k1 won the clash
        assertEq(settled.winningTotalStake, 0); // nobody predicted k1
        assertEq(oracle.protocolFeeBalance(), MIN_STAKE);
    }

    function test_SettleWithUnrevealedCommit() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   1, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        // bob does NOT reveal

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}(); // k1
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}(); // k2
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0))); // k1 wins

        oracle.progressLoop(abi.encode(uint256(1)));

        KaijuOracle.Round memory settled = oracle.getRound(1);
        assertEq(settled.winningTotalStake, MIN_STAKE); // only alice

        // alice claims full pot (minus rake) — bob's forfeited stake included
        uint256 totalPot = MIN_STAKE * 2;
        uint256 rake = (totalPot * PROTOCOL_RAKE) / 10_000;
        uint256 share = totalPot - rake;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice); oracle.claimWinnings(1);
        assertEq(alice.balance - aliceBefore, share);
    }

    function test_SettleOpensNextRound() public {
        _setupAndSettle();
        assertEq(oracle.currentRoundId(), 2);
        KaijuOracle.Round memory r2 = oracle.getRound(2);
        assertFalse(r2.settled);
        assertGt(r2.targetClashId, 0);
    }

    function test_ClaimRejectsNotSettled() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: not settled");
        oracle.claimWinnings(1);
    }

    function test_ClaimRejectsNonWinner() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   2, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(bob);   oracle.reveal(2, bytes32(uint256(43)));

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0))); // k1 wins
        oracle.progressLoop(abi.encode(uint256(1)));

        vm.prank(bob);
        vm.expectRevert("KaijuOracle: not a winner");
        oracle.claimWinnings(1);
    }

    function test_ClaimRejectsDouble() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0))); // k1 wins
        oracle.progressLoop(abi.encode(uint256(1)));

        vm.prank(alice); oracle.claimWinnings(1);
        vm.prank(alice);
        vm.expectRevert("KaijuOracle: already claimed");
        oracle.claimWinnings(1);
    }

    // ===============================================================
    //  Section 6 — shouldProgressLoop & cross-contract coordination
    // ===============================================================

    function test_ShouldProgressFalseDuringCommit() public view {
        (bool ready, ) = oracle.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressFalseDuringReveal() public {
        _warpToReveal();
        (bool ready, ) = oracle.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressFalseRevealOverClashNotResolved() public {
        KaijuOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.revealEndAt);
        (bool ready, ) = oracle.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueWhenBothConditionsMet() public {
        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0)));

        (bool ready, ) = oracle.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_SettleRejectsIfClashNotResolved() public {
        KaijuOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.revealEndAt);
        vm.expectRevert("KaijuOracle: clash not resolved");
        oracle.progressLoop(abi.encode(uint256(1)));
    }

    function test_SettleRejectsStaleRound() public {
        _setupAndSettle();
        vm.expectRevert("KaijuOracle: stale round");
        oracle.progressLoop(abi.encode(uint256(1)));
    }

    function test_SettleRejectsDuringReveal() public {
        _warpToReveal();
        vm.expectRevert("KaijuOracle: reveal open");
        oracle.progressLoop(abi.encode(uint256(1)));
    }

    function test_ClashWinnersPopulatedOnLeagueResolve() public {
        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);
        vm.warp(league.lastClashAt() + CLASH_INTERVAL);
        assertEq(league.clashWinners(1), 0); // not yet resolved
        league.tickForTest(bytes32(uint256(0)));
        assertEq(league.clashWinners(1), 1); // k1 wins
    }

    // ===============================================================
    //  Section 7 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(2, bytes32(uint256(42)));

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0))); // k1 wins; alice predicted k2
        oracle.progressLoop(abi.encode(uint256(1)));

        uint256 fee = oracle.protocolFeeBalance();
        assertEq(fee, MIN_STAKE);
        uint256 before = admin.balance;
        oracle.withdrawProtocolFees(admin, fee);
        assertEq(admin.balance - before, fee);
        assertEq(oracle.protocolFeeBalance(), 0);
    }

    function test_WithdrawRejectsNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.withdrawProtocolFees(alice, 0);
    }

    function test_WithdrawRejectsZeroAddress() public {
        vm.expectRevert("KaijuOracle: zero address");
        oracle.withdrawProtocolFees(address(0), 0);
    }

    // ===============================================================
    //  Section 8 — Fuzz tests
    // ===============================================================

    function testFuzz_WinningKaijuMatchesClash(bytes32 leagueRandomness) public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        league.tickForTest(leagueRandomness);
        oracle.progressLoop(abi.encode(uint256(1)));

        KaijuOracle.Round memory settled = oracle.getRound(1);
        assertEq(settled.winningKaijuId, league.clashWinners(1));
    }

    function testFuzz_PotAccounting(bytes32 leagueRandomness) public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   2, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(bob);   oracle.reveal(2, bytes32(uint256(43)));

        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        league.tickForTest(leagueRandomness);
        oracle.progressLoop(abi.encode(uint256(1)));

        KaijuOracle.Round memory settled = oracle.getRound(1);
        uint256 totalPot = MIN_STAKE * 2;
        uint256 rake = (totalPot * PROTOCOL_RAKE) / 10_000;

        if (settled.winningTotalStake == 0) {
            assertEq(oracle.protocolFeeBalance(), totalPot);
        } else {
            assertEq(oracle.protocolFeeBalance(), rake);
        }
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _makeCommit(
        address player,
        uint256 kaijuId,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(kaijuId, salt, player));
    }

    function _commitFor(
        address player,
        uint256 kaijuId,
        bytes32 salt,
        uint256 stake
    ) internal {
        bytes32 c = _makeCommit(player, kaijuId, salt);
        vm.prank(player);
        oracle.commit{value: stake}(c);
    }

    function _warpToReveal() internal {
        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        vm.warp(r.commitEndAt);
    }

    function _warpPastDeadlines() internal {
        KaijuOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        uint256 leagueDeadline = league.lastClashAt() + CLASH_INTERVAL;
        uint256 t = r.revealEndAt > leagueDeadline ? r.revealEndAt : leagueDeadline;
        vm.warp(t);
    }

    function _setupAndSettle() internal {
        vm.prank(alice); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(carol); league.hatchKaiju{value: KAIJU_FEE}();
        vm.prank(alice); league.enterClash{value: ENTRY_FEE}(1);
        vm.prank(carol); league.enterClash{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        league.tickForTest(bytes32(uint256(0)));
        oracle.progressLoop(abi.encode(oracle.currentRoundId()));
    }
}
