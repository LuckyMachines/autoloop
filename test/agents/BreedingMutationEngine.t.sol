// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/BreedingMutationEngine.sol";

contract BreedingMutationEngineHarness is BreedingMutationEngine {
    constructor(uint256 _cooldown, uint256 _fee)
        BreedingMutationEngine(_cooldown, _fee) {}

    function tickForTest(bytes32 randomness) external {
        require(breedingQueue.length > 0, "BreedingEngine: queue empty");
        require((block.timestamp - lastBreed) >= breedingCooldown, "BreedingEngine: too soon");
        lastBreed = block.timestamp;
        ++_loopID;
        _processFirstPair(randomness);
    }
}

contract BreedingMutationEngineTest is Test {
    BreedingMutationEngineHarness public be;
    uint256 public cooldown = 1 hours;
    uint256 public fee      = 0.01 ether;

    address public alice = address(0xA1);
    address public bob   = address(0xB2);

    function setUp() public {
        be = new BreedingMutationEngineHarness(cooldown, fee);
        vm.deal(alice, 10 ether);
        vm.deal(bob,   10 ether);
    }

    // ── Construction ──────────────────────────────────────────────────────────

    function test_ConstructorZeroCooldownReverts() public {
        vm.expectRevert("BreedingEngine: cooldown=0");
        new BreedingMutationEngineHarness(0, fee);
    }

    function test_TraitNames() public view {
        assertEq(be.traitNames(0), "Strength");
        assertEq(be.traitNames(4), "Luck");
    }

    function test_InitialState() public view {
        assertEq(be.breedingCooldown(), cooldown);
        assertEq(be.breedingFee(), fee);
        assertEq(be.nextTokenId(), 0);
        assertEq(be.queueLength(), 0);
    }

    // ── mint ──────────────────────────────────────────────────────────────────

    function test_MintCreatesToken() public {
        vm.prank(alice);
        uint256 tokenId = be.mint();
        assertEq(tokenId, 0);
        assertEq(be.ownerOf(0), alice);
        assertEq(be.nextTokenId(), 1);
    }

    function test_MintEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit BreedingMutationEngine.TokenMinted(0, alice, [uint8(0),0,0,0,0]);
        be.mint();
    }

    function test_MintedTraitsInRange() public {
        vm.prank(alice);
        be.mint();
        uint8[5] memory t = be.getTraits(0);
        for (uint256 i = 0; i < 5; i++) {
            assertGt(t[i], 0);
            assertLe(t[i], 100);
        }
    }

    function test_MultipleMints() public {
        vm.prank(alice);
        be.mint();
        vm.prank(alice);
        be.mint();
        assertEq(be.nextTokenId(), 2);
    }

    // ── queueBreeding ─────────────────────────────────────────────────────────

    function _mintTwo() internal returns (uint256 t1, uint256 t2) {
        vm.prank(alice);
        t1 = be.mint();
        vm.prank(alice);
        t2 = be.mint();
    }

    function test_QueueBreeding() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        uint256 pairId = be.queueBreeding{value: fee}(t1, t2);
        assertEq(pairId, 0);
        assertEq(be.queueLength(), 1);
    }

    function test_QueueBreedingEmitsEvent() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        vm.expectEmit(false, false, false, false);
        emit BreedingMutationEngine.BreedingQueued(0, t1, t2, alice);
        be.queueBreeding{value: fee}(t1, t2);
    }

    function test_QueueBreedingNotOwnerReverts() public {
        (uint256 t1,) = _mintTwo();
        // Mint a token for bob
        vm.prank(bob);
        uint256 t3 = be.mint();
        vm.prank(alice);
        vm.expectRevert("BreedingEngine: not owner of parent2");
        be.queueBreeding{value: fee}(t1, t3);
    }

    function test_QueueBreedingSameTokenReverts() public {
        (uint256 t1,) = _mintTwo();
        vm.prank(alice);
        vm.expectRevert("BreedingEngine: same token");
        be.queueBreeding{value: fee}(t1, t1);
    }

    function test_QueueBreedingInsufficientFeeReverts() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        vm.expectRevert("BreedingEngine: insufficient fee");
        be.queueBreeding{value: fee - 1}(t1, t2);
    }

    function test_QueueBreedingAccruesFee() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        assertGt(be.protocolFeeBalance(), 0);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyEmptyQueue() public view {
        (bool ready,) = be.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_NotReadyBeforeCooldown() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        (bool ready,) = be.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterCooldown() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.warp(block.timestamp + cooldown);
        (bool ready,) = be.shouldProgressLoop();
        assertTrue(ready);
    }

    // ── tickForTest ───────────────────────────────────────────────────────────

    function test_BreedingProducesOffspring() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.warp(block.timestamp + cooldown);
        be.tickForTest(keccak256("seed"));
        assertEq(be.nextTokenId(), 3); // 2 parents + 1 offspring
    }

    function test_OffspringOwnedByQueueOwner() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.warp(block.timestamp + cooldown);
        be.tickForTest(keccak256("seed"));
        assertEq(be.ownerOf(2), alice);
    }

    function test_OffspringTraitsInRange() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.warp(block.timestamp + cooldown);
        be.tickForTest(keccak256("seed"));
        uint8[5] memory t = be.getTraits(2);
        for (uint256 i = 0; i < 5; i++) {
            assertGt(t[i], 0);
            assertLe(t[i], 100);
        }
    }

    function test_BreedingEmitsEvent() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.warp(block.timestamp + cooldown);
        vm.recordLogs();
        be.tickForTest(keccak256("seed"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BreedingMutationEngine.BreedingComplete.selector) found = true;
        }
        assertTrue(found);
    }

    function test_QueueDecrementsAfterBreeding() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        assertEq(be.queueLength(), 1);
        vm.warp(block.timestamp + cooldown);
        be.tickForTest(keccak256("seed"));
        assertEq(be.queueLength(), 0);
    }

    function test_TooSoonReverts() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.expectRevert("BreedingEngine: too soon");
        be.tickForTest(keccak256("seed"));
    }

    function test_EmptyQueueReverts() public {
        vm.warp(block.timestamp + cooldown);
        vm.expectRevert("BreedingEngine: queue empty");
        be.tickForTest(keccak256("seed"));
    }

    function test_MultipleQueuedPairsProcessSequentially() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);

        // Third and fourth tokens for second pair
        vm.prank(alice); uint256 t3 = be.mint();
        vm.prank(alice); uint256 t4 = be.mint();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t3, t4);
        assertEq(be.queueLength(), 2);

        vm.warp(block.timestamp + cooldown);
        be.tickForTest(keccak256("a")); // processes first pair
        assertEq(be.queueLength(), 1);

        vm.warp(block.timestamp + cooldown);
        be.tickForTest(keccak256("b")); // processes second pair
        assertEq(be.queueLength(), 0);
        assertEq(be.nextTokenId(), 6); // 4 originals + 2 offspring
    }

    // ── admin ─────────────────────────────────────────────────────────────────

    function test_SetBreedingCooldown() public {
        be.setBreedingCooldown(2 hours);
        assertEq(be.breedingCooldown(), 2 hours);
    }

    function test_SetBreedingCooldownZeroReverts() public {
        vm.expectRevert("BreedingEngine: cooldown=0");
        be.setBreedingCooldown(0);
    }

    function test_SetBreedingFee() public {
        be.setBreedingFee(0.05 ether);
        assertEq(be.breedingFee(), 0.05 ether);
    }

    function test_WithdrawProtocolFees() public {
        (uint256 t1, uint256 t2) = _mintTwo();
        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        uint256 fees = be.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xFEED);
        be.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
        assertEq(be.protocolFeeBalance(), 0);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_OffspringTraitsAlwaysInheritsOrMutates(bytes32 seed) public {
        (uint256 t1, uint256 t2) = _mintTwo();
        uint8[5] memory p1 = be.getTraits(t1);
        uint8[5] memory p2 = be.getTraits(t2);

        vm.prank(alice);
        be.queueBreeding{value: fee}(t1, t2);
        vm.warp(block.timestamp + cooldown);
        be.tickForTest(seed);

        uint8[5] memory offspring = be.getTraits(2);
        for (uint256 i = 0; i < 5; i++) {
            // Must be in range 1..100 and either match a parent or be a mutation
            assertGt(offspring[i], 0);
            assertLe(offspring[i], 100);
            // It's either from parent1, parent2, or a mutation (different from both)
            bool inheritsP1 = offspring[i] == p1[i];
            bool inheritsP2 = offspring[i] == p2[i];
            bool isMutation = (!inheritsP1 && !inheritsP2);
            // All 3 options are valid
            assertTrue(inheritsP1 || inheritsP2 || isMutation);
        }
    }

    receive() external payable {}
}
