// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/GladiatorArena.sol";
import "../../src/games/GladiatorOracle.sol";

// ===============================================================
//  Arena harness — exposes _progressInternal for deterministic tests
// ===============================================================

contract ArenaForOracle is GladiatorArena {
    constructor(
        uint256 a, uint256 b, uint256 c,
        uint256 d, uint32 e, uint32 f, uint256 g
    ) GladiatorArena(a, b, c, d, e, f, g) {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }
}

// ===============================================================
//  Test suite
// ===============================================================

contract GladiatorOracleTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    ArenaForOracle public arena;
    GladiatorOracle public oracle;

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
    uint256 constant GLADIATOR_FEE   = 0.01 ether;
    uint256 constant ENTRY_FEE       = 0.001 ether;
    uint256 constant BOUT_INTERVAL   = 60;

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

        arena = new ArenaForOracle(
            GLADIATOR_FEE, ENTRY_FEE, BOUT_INTERVAL, PROTOCOL_RAKE,
            500, 50, 8
        );
        registrar.registerAutoLoopFor(address(arena), 2_000_000);
        registrar.deposit{value: 10 ether}(address(arena));

        oracle = new GladiatorOracle(
            address(arena),
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
        GladiatorOracle.Round memory r = oracle.getRound(1);
        assertFalse(r.settled);
        assertEq(r.totalPot, 0);
        assertEq(r.targetBoutId, arena.currentBoutId());
    }

    function test_Immutables() public view {
        assertEq(oracle.commitDuration(), COMMIT_DURATION);
        assertEq(oracle.revealDuration(), REVEAL_DURATION);
        assertEq(oracle.minStake(), MIN_STAKE);
        assertEq(oracle.protocolRakeBps(), PROTOCOL_RAKE);
        assertEq(address(oracle.gladiatorArena()), address(arena));
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroArena() public {
        vm.expectRevert("GladiatorOracle: arena=0");
        new GladiatorOracle(address(0), COMMIT_DURATION, REVEAL_DURATION, MIN_STAKE, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroCommit() public {
        vm.expectRevert("GladiatorOracle: commit=0");
        new GladiatorOracle(address(arena), 0, REVEAL_DURATION, MIN_STAKE, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroReveal() public {
        vm.expectRevert("GladiatorOracle: reveal=0");
        new GladiatorOracle(address(arena), COMMIT_DURATION, 0, MIN_STAKE, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsZeroStake() public {
        vm.expectRevert("GladiatorOracle: stake=0");
        new GladiatorOracle(address(arena), COMMIT_DURATION, REVEAL_DURATION, 0, PROTOCOL_RAKE);
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("GladiatorOracle: rake > 20%");
        new GladiatorOracle(address(arena), COMMIT_DURATION, REVEAL_DURATION, MIN_STAKE, 2001);
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
        assertEq(oracle.revealedGladiators(1, alice), oracle.GLADIATOR_UNREVEALED());

        GladiatorOracle.Round memory r = oracle.getRound(1);
        assertEq(r.totalPot, MIN_STAKE);
    }

    function test_CommitRejectsLowStake() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: stake too low");
        oracle.commit{value: MIN_STAKE - 1}(c);
    }

    function test_CommitRejectsDouble() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: already committed");
        oracle.commit{value: MIN_STAKE}(c);
    }

    function test_CommitRejectsEmpty() public {
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: empty commit");
        oracle.commit{value: MIN_STAKE}(bytes32(0));
    }

    function test_CommitRejectsAfterCommitPhase() public {
        GladiatorOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.commitEndAt);

        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: commit phase over");
        oracle.commit{value: MIN_STAKE}(c);
    }

    function test_CommitEmitsEvent() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(42)));
        vm.expectEmit(true, true, false, true, address(oracle));
        emit GladiatorOracle.Committed(1, alice, MIN_STAKE, c);
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

        assertEq(oracle.revealedGladiators(1, alice), 1);
        assertEq(oracle.revealedTotalPerGladiator(1, 1), MIN_STAKE);
        assertEq(oracle.revealedCountPerGladiator(1, 1), 1);
    }

    function test_RevealRejectsBeforeCommitPhaseEnd() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: still commit phase");
        oracle.reveal(1, bytes32(uint256(42)));
    }

    function test_RevealRejectsAfterRevealPhase() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        GladiatorOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.revealEndAt);
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: reveal phase over");
        oracle.reveal(1, bytes32(uint256(42)));
    }

    function test_RevealRejectsBadSalt() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: bad reveal");
        oracle.reveal(1, bytes32(uint256(99)));
    }

    function test_RevealRejectsBadGladiatorId() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: bad reveal");
        oracle.reveal(2, bytes32(uint256(42)));
    }

    function test_RevealRejectsDouble() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: already revealed");
        oracle.reveal(1, bytes32(uint256(42)));
    }

    function test_RevealRejectsZeroGladiator() public {
        bytes32 c = keccak256(abi.encode(uint256(0), bytes32(uint256(1)), alice));
        vm.prank(alice);
        oracle.commit{value: MIN_STAKE}(c);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: invalid gladiator");
        oracle.reveal(0, bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 5 — Settlement & payout (cross-contract integration)
    // ===============================================================

    function test_SettleWithWinners() public {
        // alice and bob predict gladiator 1; carol predicts gladiator 2
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   1, bytes32(uint256(43)), MIN_STAKE);
        _commitFor(carol, 2, bytes32(uint256(44)), MIN_STAKE);

        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(bob);   oracle.reveal(1, bytes32(uint256(43)));
        vm.prank(carol); oracle.reveal(2, bytes32(uint256(44)));

        // Enter two gladiators into the arena bout
        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}(); // g1
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}(); // g2
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);

        // Resolve arena. rand=0 → winningWeight=0, first entrant (g1) wins.
        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0)));
        assertEq(arena.boutWinners(1), 1); // bout 1, winner = gladiator 1

        // Settle oracle
        oracle.progressLoop(abi.encode(uint256(1)));

        GladiatorOracle.Round memory settled = oracle.getRound(1);
        assertTrue(settled.settled);
        assertEq(settled.winningGladiatorId, 1);
        assertEq(settled.winningTotalStake, MIN_STAKE * 2); // alice + bob

        uint256 totalPot = MIN_STAKE * 3;
        uint256 rake = (totalPot * PROTOCOL_RAKE) / 10_000;
        uint256 share = (totalPot - rake) / 2;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        oracle.claimWinnings(1);
        assertEq(alice.balance - aliceBefore, share);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        oracle.claimWinnings(1);
        assertEq(bob.balance - bobBefore, share);

        assertEq(oracle.protocolFeeBalance(), rake);
    }

    function test_SettleWithNoWinners() public {
        // alice predicts gladiator 2, but gladiator 1 wins → no winners
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(2, bytes32(uint256(42)));

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}(); // g1
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}(); // g2
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0))); // g1 wins

        oracle.progressLoop(abi.encode(uint256(1)));

        GladiatorOracle.Round memory settled = oracle.getRound(1);
        assertEq(settled.winningGladiatorId, 1); // g1 won the bout
        assertEq(settled.winningTotalStake, 0);  // nobody predicted g1
        // Entire pot to protocol
        assertEq(oracle.protocolFeeBalance(), MIN_STAKE);
    }

    function test_SettleWithUnrevealedCommit() public {
        // alice reveals, bob does not — bob's stake goes to pot but doesn't count
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   1, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        // bob does NOT reveal

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}(); // g1
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}(); // g2
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0))); // g1 wins

        oracle.progressLoop(abi.encode(uint256(1)));

        GladiatorOracle.Round memory settled = oracle.getRound(1);
        assertEq(settled.winningTotalStake, MIN_STAKE); // only alice

        // alice claims full pot (minus rake) — bob's forfeited stake included
        uint256 totalPot = MIN_STAKE * 2;
        uint256 rake = (totalPot * PROTOCOL_RAKE) / 10_000;
        uint256 share = totalPot - rake;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        oracle.claimWinnings(1);
        assertEq(alice.balance - aliceBefore, share);
    }

    function test_SettleOpensNextRound() public {
        _setupAndSettle();
        assertEq(oracle.currentRoundId(), 2);
        GladiatorOracle.Round memory r2 = oracle.getRound(2);
        assertFalse(r2.settled);
        // targetBoutId for round 2 should be arena.currentBoutId() at settlement time
        assertGt(r2.targetBoutId, 0);
    }

    function test_ClaimRejectsNotSettled() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: not settled");
        oracle.claimWinnings(1);
    }

    function test_ClaimRejectsNonWinner() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   2, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(bob);   oracle.reveal(2, bytes32(uint256(43)));

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0))); // g1 wins
        oracle.progressLoop(abi.encode(uint256(1)));

        vm.prank(bob);
        vm.expectRevert("GladiatorOracle: not a winner");
        oracle.claimWinnings(1);
    }

    function test_ClaimRejectsDouble() public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);

        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0))); // g1 wins
        oracle.progressLoop(abi.encode(uint256(1)));

        vm.prank(alice); oracle.claimWinnings(1);
        vm.prank(alice);
        vm.expectRevert("GladiatorOracle: already claimed");
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

    function test_ShouldProgressFalseRevealOverBoutNotResolved() public {
        // Warp past revealEndAt, but arena bout has NOT been resolved
        GladiatorOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.revealEndAt);
        (bool ready, ) = oracle.shouldProgressLoop();
        assertFalse(ready); // bout not resolved yet
    }

    function test_ShouldProgressTrueWhenBothConditionsMet() public {
        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0)));

        (bool ready, ) = oracle.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_SettleRejectsIfBoutNotResolved() public {
        GladiatorOracle.Round memory r = oracle.getRound(1);
        vm.warp(r.revealEndAt);
        vm.expectRevert("GladiatorOracle: bout not resolved");
        oracle.progressLoop(abi.encode(uint256(1)));
    }

    function test_SettleRejectsStaleRound() public {
        _setupAndSettle();
        // Round 2 is now current; try to settle with round 1 id
        vm.expectRevert("GladiatorOracle: stale round");
        oracle.progressLoop(abi.encode(uint256(1)));
    }

    function test_SettleRejectsDuringReveal() public {
        _warpToReveal();
        vm.expectRevert("GladiatorOracle: reveal open");
        oracle.progressLoop(abi.encode(uint256(1)));
    }

    function test_BoutWinnersPopulatedOnArenaResolve() public {
        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);
        vm.warp(arena.lastBoutAt() + BOUT_INTERVAL);
        assertEq(arena.boutWinners(1), 0); // not yet resolved
        arena.tickForTest(bytes32(uint256(0)));
        assertEq(arena.boutWinners(1), 1); // g1 wins
    }

    // ===============================================================
    //  Section 7 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        // No winners → all fees to protocol
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(2, bytes32(uint256(42)));

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0))); // g1 wins; alice predicted g2
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
        vm.expectRevert("GladiatorOracle: zero address");
        oracle.withdrawProtocolFees(address(0), 0);
    }

    // ===============================================================
    //  Section 8 — Fuzz tests
    // ===============================================================

    /// @dev Winning gladiator always matches boutWinners.
    function testFuzz_WinningGladiatorMatchesBout(bytes32 arenaRandomness) public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        arena.tickForTest(arenaRandomness);
        oracle.progressLoop(abi.encode(uint256(1)));

        GladiatorOracle.Round memory settled = oracle.getRound(1);
        assertEq(settled.winningGladiatorId, arena.boutWinners(1));
    }

    /// @dev Pot is always fully allocated after settlement.
    function testFuzz_PotAccounting(bytes32 arenaRandomness) public {
        _commitFor(alice, 1, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob,   2, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice); oracle.reveal(1, bytes32(uint256(42)));
        vm.prank(bob);   oracle.reveal(2, bytes32(uint256(43)));

        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        arena.tickForTest(arenaRandomness);
        oracle.progressLoop(abi.encode(uint256(1)));

        GladiatorOracle.Round memory settled = oracle.getRound(1);
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
        uint256 gladiatorId,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(gladiatorId, salt, player));
    }

    function _commitFor(
        address player,
        uint256 gladiatorId,
        bytes32 salt,
        uint256 stake
    ) internal {
        bytes32 c = _makeCommit(player, gladiatorId, salt);
        vm.prank(player);
        oracle.commit{value: stake}(c);
    }

    function _warpToReveal() internal {
        GladiatorOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        vm.warp(r.commitEndAt);
    }

    /// @dev Warp past both oracle revealEndAt and arena boutInterval.
    function _warpPastDeadlines() internal {
        GladiatorOracle.Round memory r = oracle.getRound(oracle.currentRoundId());
        uint256 arenaDeadline = arena.lastBoutAt() + BOUT_INTERVAL;
        uint256 t = r.revealEndAt > arenaDeadline ? r.revealEndAt : arenaDeadline;
        vm.warp(t);
    }

    /// @dev Full happy-path settle: 2 arena entrants, resolve bout, settle oracle.
    function _setupAndSettle() internal {
        vm.prank(alice); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(carol); arena.mintGladiator{value: GLADIATOR_FEE}();
        vm.prank(alice); arena.enterBout{value: ENTRY_FEE}(1);
        vm.prank(carol); arena.enterBout{value: ENTRY_FEE}(2);
        _warpPastDeadlines();
        arena.tickForTest(bytes32(uint256(0)));
        oracle.progressLoop(abi.encode(oracle.currentRoundId()));
    }
}
