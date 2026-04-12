// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import "../../src/AutoLoop.sol";
import "../../src/AutoLoopRegistry.sol";
import "../../src/AutoLoopRegistrar.sol";
import "../../src/AutoLoopCompatibleInterface.sol";
import "../../src/games/PhantomDriver.sol";

/// @notice Test harness exposing `_progressInternal` for deterministic tests.
contract PhantomDriverHarness is PhantomDriver {
    constructor(
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _minStake,
        uint256 _protocolRakeBps
    )
        PhantomDriver(
            _commitDuration,
            _revealDuration,
            _minStake,
            _protocolRakeBps
        )
    {}

    function tickForTest(bytes32 randomness) external {
        _progressInternal(randomness, _loopID);
    }

    function tickForTestRaw(bytes32 randomness, uint256 loopId) external {
        _progressInternal(randomness, loopId);
    }
}

contract PhantomDriverTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    PhantomDriverHarness public game;

    address public proxyAdmin;
    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public dave;
    address public controller1;

    uint256 constant COMMIT_DURATION = 120;
    uint256 constant REVEAL_DURATION = 120;
    uint256 constant MIN_STAKE = 0.001 ether;
    uint256 constant PROTOCOL_RAKE_BPS = 500;
    uint256 constant GAS_PRICE = 20 gwei;

    receive() external payable {}

    function setUp() public {
        proxyAdmin = vm.addr(99);
        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        carol = vm.addr(0xCA20A);
        dave = vm.addr(0xDA5E);
        controller1 = vm.addr(0xC0DE);
        admin = address(this);

        vm.deal(admin, 1000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(dave, 100 ether);
        vm.deal(controller1, 100 ether);

        AutoLoop autoLoopImpl = new AutoLoop();
        TransparentUpgradeableProxy autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(string)", "0.0.1")
        );
        autoLoop = AutoLoop(address(autoLoopProxy));

        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        TransparentUpgradeableProxy registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(address)", admin)
        );
        registry = AutoLoopRegistry(address(registryProxy));

        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();
        TransparentUpgradeableProxy registrarProxy = new TransparentUpgradeableProxy(
            address(registrarImpl),
            proxyAdmin,
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(autoLoop),
                address(registry),
                admin
            )
        );
        registrar = AutoLoopRegistrar(address(registrarProxy));

        registry.setRegistrar(address(registrar));
        autoLoop.setRegistrar(address(registrar));

        game = new PhantomDriverHarness(
            COMMIT_DURATION,
            REVEAL_DURATION,
            MIN_STAKE,
            PROTOCOL_RAKE_BPS
        );
        registrar.registerAutoLoopFor(address(game), 2_000_000);

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();
        registrar.deposit{value: 10 ether}(address(game));
    }

    // ===============================================================
    //  Section 1 — Initial state & interfaces
    // ===============================================================

    function test_SupportsVRFInterface() public view {
        assertTrue(
            game.supportsInterface(bytes4(keccak256("AutoLoopVRFCompatible")))
        );
    }

    function test_InitialState() public view {
        assertEq(game.currentRoundId(), 1);
        assertEq(game.protocolFeeBalance(), 0);
        PhantomDriver.Round memory r = game.getRound(1);
        assertFalse(r.resolved);
        assertEq(r.totalPot, 0);
    }

    function test_Immutables() public view {
        assertEq(game.commitDuration(), COMMIT_DURATION);
        assertEq(game.revealDuration(), REVEAL_DURATION);
        assertEq(game.minStake(), MIN_STAKE);
        assertEq(game.protocolRakeBps(), PROTOCOL_RAKE_BPS);
    }

    // ===============================================================
    //  Section 2 — Constructor validation
    // ===============================================================

    function test_ConstructorRejectsZeroCommit() public {
        vm.expectRevert("PhantomDriver: commit=0");
        new PhantomDriverHarness(0, REVEAL_DURATION, MIN_STAKE, PROTOCOL_RAKE_BPS);
    }

    function test_ConstructorRejectsZeroReveal() public {
        vm.expectRevert("PhantomDriver: reveal=0");
        new PhantomDriverHarness(COMMIT_DURATION, 0, MIN_STAKE, PROTOCOL_RAKE_BPS);
    }

    function test_ConstructorRejectsZeroStake() public {
        vm.expectRevert("PhantomDriver: stake=0");
        new PhantomDriverHarness(COMMIT_DURATION, REVEAL_DURATION, 0, PROTOCOL_RAKE_BPS);
    }

    function test_ConstructorRejectsHighRake() public {
        vm.expectRevert("PhantomDriver: rake > 20%");
        new PhantomDriverHarness(COMMIT_DURATION, REVEAL_DURATION, MIN_STAKE, 2001);
    }

    // ===============================================================
    //  Section 3 — Commit phase
    // ===============================================================

    function test_Commit() public {
        bytes32 c = _makeCommit(alice, 2, bytes32(uint256(42)));
        vm.prank(alice);
        game.commit{value: MIN_STAKE}(c);

        assertEq(game.commits(1, alice), c);
        assertEq(game.stakes(1, alice), MIN_STAKE);
        assertEq(game.revealedRoles(1, alice), game.ROLE_UNREVEALED());

        PhantomDriver.Round memory r = game.getRound(1);
        assertEq(r.totalPot, MIN_STAKE);
    }

    function test_CommitRejectsLowStake() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: stake too low");
        game.commit{value: MIN_STAKE - 1}(c);
    }

    function test_CommitRejectsDouble() public {
        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        game.commit{value: MIN_STAKE}(c);
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: already committed");
        game.commit{value: MIN_STAKE}(c);
    }

    function test_CommitRejectsEmpty() public {
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: empty commit");
        game.commit{value: MIN_STAKE}(bytes32(0));
    }

    function test_CommitRejectsAfterCommitPhase() public {
        PhantomDriver.Round memory r = game.getRound(1);
        vm.warp(r.commitEndAt);

        bytes32 c = _makeCommit(alice, 1, bytes32(uint256(1)));
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: commit phase over");
        game.commit{value: MIN_STAKE}(c);
    }

    function test_CommitEmitsEvent() public {
        bytes32 c = _makeCommit(alice, 2, bytes32(uint256(42)));
        vm.expectEmit(true, true, false, true, address(game));
        emit PhantomDriver.Committed(1, alice, MIN_STAKE, c);
        vm.prank(alice);
        game.commit{value: MIN_STAKE}(c);
    }

    // ===============================================================
    //  Section 4 — Reveal phase
    // ===============================================================

    function test_Reveal() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();

        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));
        assertEq(game.revealedRoles(1, alice), 2);
        assertEq(game.revealedTotalPerRole(1, 2), MIN_STAKE);
        assertEq(game.revealedCountPerRole(1, 2), 1);
    }

    function test_RevealRejectsBeforeCommitPhaseEnd() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: still commit phase");
        game.reveal(2, bytes32(uint256(42)));
    }

    function test_RevealRejectsAfterRevealPhase() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        PhantomDriver.Round memory r = game.getRound(1);
        vm.warp(r.revealEndAt);
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: reveal phase over");
        game.reveal(2, bytes32(uint256(42)));
    }

    function test_RevealRejectsBadSalt() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: bad reveal");
        game.reveal(2, bytes32(uint256(99)));
    }

    function test_RevealRejectsBadRole() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: bad reveal");
        game.reveal(3, bytes32(uint256(42)));
    }

    function test_RevealRejectsDouble() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: already revealed");
        game.reveal(2, bytes32(uint256(42)));
    }

    function test_RevealRejectsOutOfRangeRole() public {
        // Use a role >= NUM_ROLES (4)
        bytes32 c = keccak256(abi.encode(uint8(5), bytes32(uint256(1)), alice));
        vm.prank(alice);
        game.commit{value: MIN_STAKE}(c);
        _warpToReveal();
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: bad role");
        game.reveal(5, bytes32(uint256(1)));
    }

    // ===============================================================
    //  Section 5 — Resolution & payout
    // ===============================================================

    function test_ResolveWithWinners() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob, 2, bytes32(uint256(43)), MIN_STAKE);
        _commitFor(carol, 1, bytes32(uint256(44)), MIN_STAKE);

        _warpToReveal();
        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));
        vm.prank(bob);
        game.reveal(2, bytes32(uint256(43)));
        vm.prank(carol);
        game.reveal(1, bytes32(uint256(44)));

        _warpToResolve();

        // Seed randomness so winningRole = 2 (2 % 4 = 2)
        bytes32 r = bytes32(uint256(2));
        game.tickForTest(r);

        PhantomDriver.Round memory round = game.getRound(1);
        assertTrue(round.resolved);
        assertEq(round.winningRole, 2);
        assertEq(round.winningTotalStake, MIN_STAKE * 2);

        // alice and bob each claim half the pot (minus rake)
        uint256 totalPot = MIN_STAKE * 3;
        uint256 rake = (totalPot * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 share = (totalPot - rake) / 2;

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.claimWinnings(1);
        assertEq(alice.balance - aliceBefore, share);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        game.claimWinnings(1);
        assertEq(bob.balance - bobBefore, share);

        assertEq(game.protocolFeeBalance(), rake);
    }

    function test_ResolveWithNoWinners() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));

        _warpToResolve();
        // winningRole = 0 → alice loses
        bytes32 r = bytes32(uint256(0));
        game.tickForTest(r);

        PhantomDriver.Round memory round = game.getRound(1);
        assertEq(round.winningRole, 0);
        assertEq(round.winningTotalStake, 0);

        // All pot accrues to protocol
        assertEq(game.protocolFeeBalance(), MIN_STAKE);
    }

    function test_ResolveWithUnrevealedCommit() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob, 2, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        // Alice reveals, Bob doesn't
        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));

        _warpToResolve();
        bytes32 r = bytes32(uint256(2));
        game.tickForTest(r);

        PhantomDriver.Round memory round = game.getRound(1);
        assertEq(round.winningTotalStake, MIN_STAKE); // only alice

        // Alice claims — but the pot is the FULL pot (alice + bob)
        uint256 totalPot = MIN_STAKE * 2;
        uint256 rake = (totalPot * PROTOCOL_RAKE_BPS) / 10_000;
        uint256 share = totalPot - rake; // alice is sole winner

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        game.claimWinnings(1);
        assertEq(alice.balance - aliceBefore, share);
    }

    function test_ClaimRejectsNotResolved() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        vm.prank(alice);
        vm.expectRevert("PhantomDriver: not resolved");
        game.claimWinnings(1);
    }

    function test_ClaimRejectsNonWinner() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob, 1, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));
        vm.prank(bob);
        game.reveal(1, bytes32(uint256(43)));

        _warpToResolve();
        game.tickForTest(bytes32(uint256(2))); // role 2 wins

        vm.prank(bob);
        vm.expectRevert("PhantomDriver: not a winner");
        game.claimWinnings(1);
    }

    function test_ClaimRejectsDouble() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob, 2, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        game.reveal(2, bytes32(uint256(42)));
        vm.prank(bob);
        game.reveal(2, bytes32(uint256(43)));

        _warpToResolve();
        game.tickForTest(bytes32(uint256(2)));

        vm.prank(alice);
        game.claimWinnings(1);

        vm.prank(alice);
        vm.expectRevert("PhantomDriver: already claimed");
        game.claimWinnings(1);
    }

    // ===============================================================
    //  Section 6 — Loop progression
    // ===============================================================

    function test_ShouldProgressFalseDuringCommit() public view {
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressFalseDuringReveal() public {
        _warpToReveal();
        (bool ready, ) = game.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ShouldProgressTrueAfterReveal() public {
        _warpToResolve();
        (bool ready, ) = game.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_ResolveOpensNextRound() public {
        _warpToResolve();
        game.tickForTest(bytes32(uint256(1)));
        assertEq(game.currentRoundId(), 2);
        PhantomDriver.Round memory r = game.getRound(2);
        assertFalse(r.resolved);
    }

    function test_ResolveRejectsDuringReveal() public {
        _warpToReveal();
        vm.expectRevert("PhantomDriver: reveal phase open");
        game.tickForTest(bytes32(uint256(1)));
    }

    function test_ResolveRejectsStaleLoopID() public {
        _warpToResolve();
        vm.expectRevert("PhantomDriver: stale loop id");
        game.tickForTestRaw(bytes32(uint256(1)), 999);
    }

    // ===============================================================
    //  Section 7 — Admin
    // ===============================================================

    function test_WithdrawProtocolFees() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToResolve();
        game.tickForTest(bytes32(uint256(0))); // no winners → all to protocol

        uint256 fee = game.protocolFeeBalance();
        uint256 before = admin.balance;
        game.withdrawProtocolFees(admin, fee);
        assertEq(admin.balance - before, fee);
    }

    function test_WithdrawRejectsNonAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        game.withdrawProtocolFees(alice, 0);
    }

    // ===============================================================
    //  Section 8 — VRF rejection path
    // ===============================================================

    function test_RejectsUnregisteredControllerVRF() public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToResolve();

        bytes memory gameData = abi.encode(uint256(1));
        bytes memory vrfEnvelope = abi.encode(
            uint8(1),
            [uint256(1), uint256(2), uint256(3), uint256(4)],
            [uint256(1), uint256(2)],
            [uint256(1), uint256(2), uint256(3), uint256(4)],
            gameData
        );

        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        vm.expectRevert("Unable to progress loop. Call not a success");
        autoLoop.progressLoop(address(game), vrfEnvelope);
    }

    // ===============================================================
    //  Section 9 — Fuzz tests
    // ===============================================================

    /// @dev Winning role is always in [0, NUM_ROLES-1].
    function testFuzz_WinningRoleInRange(bytes32 randomness) public {
        _commitFor(alice, 2, bytes32(uint256(42)), MIN_STAKE);
        _warpToResolve();
        game.tickForTest(randomness);

        PhantomDriver.Round memory round = game.getRound(1);
        assertLt(round.winningRole, game.NUM_ROLES());
    }

    /// @dev Pot is always fully allocated: rake + winner shares + forfeited.
    function testFuzz_PotAccounting(bytes32 randomness, uint8 aliceRole, uint8 bobRole) public {
        aliceRole = uint8(bound(uint256(aliceRole), 0, 3));
        bobRole = uint8(bound(uint256(bobRole), 0, 3));

        _commitFor(alice, aliceRole, bytes32(uint256(42)), MIN_STAKE);
        _commitFor(bob, bobRole, bytes32(uint256(43)), MIN_STAKE);
        _warpToReveal();
        vm.prank(alice);
        game.reveal(aliceRole, bytes32(uint256(42)));
        vm.prank(bob);
        game.reveal(bobRole, bytes32(uint256(43)));

        _warpToResolve();
        game.tickForTest(randomness);

        PhantomDriver.Round memory round = game.getRound(1);
        uint256 totalPot = MIN_STAKE * 2;
        uint256 rake = (totalPot * PROTOCOL_RAKE_BPS) / 10_000;

        if (round.winningTotalStake == 0) {
            // Everything to protocol
            assertEq(game.protocolFeeBalance(), totalPot);
        } else {
            // Winners claim totalPot - rake; unclaimed stays in contract
            assertEq(game.protocolFeeBalance(), rake);
        }
    }

    // ===============================================================
    //  Helpers
    // ===============================================================

    function _makeCommit(
        address player,
        uint8 role,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(role, salt, player));
    }

    function _commitFor(
        address player,
        uint8 role,
        bytes32 salt,
        uint256 stake
    ) internal {
        bytes32 c = _makeCommit(player, role, salt);
        vm.prank(player);
        game.commit{value: stake}(c);
    }

    function _warpToReveal() internal {
        PhantomDriver.Round memory r = game.getRound(game.currentRoundId());
        vm.warp(r.commitEndAt);
    }

    function _warpToResolve() internal {
        PhantomDriver.Round memory r = game.getRound(game.currentRoundId());
        vm.warp(r.revealEndAt);
    }
}
