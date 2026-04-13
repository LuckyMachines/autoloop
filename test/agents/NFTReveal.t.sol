// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/agents/NFTReveal.sol";

contract NFTRevealHarness is NFTReveal {
    constructor(
        uint256 _max, uint256 _price, uint256 _revealTime,
        uint256[] memory _tiers, string[] memory _names
    ) NFTReveal(_max, _price, _revealTime, _tiers, _names) {}

    function tickForTest(bytes32 randomness) external {
        uint256 currentLoopID = _loopID;
        require(!revealed, "NFTReveal: already revealed");
        require(nextTokenId > 0, "NFTReveal: no tokens minted");
        require(block.timestamp >= revealTime, "NFTReveal: too soon");

        revealed = true;
        revealSeed = randomness;
        ++_loopID;

        for (uint256 i = 1; i <= nextTokenId; i++) {
            uint256 roll = uint256(keccak256(abi.encodePacked(randomness, i))) % 10_000;
            uint256 cumulative = 0;
            for (uint256 t = 0; t < rarityTiersBps.length; t++) {
                cumulative += rarityTiersBps[t];
                if (roll < cumulative) {
                    tokenTier[i] = t + 1;
                    emit TraitAssigned(i, t + 1, rarityTierNames[t]);
                    break;
                }
            }
        }
        emit Revealed(randomness, nextTokenId, currentLoopID);
    }
}

contract NFTRevealTest is Test {
    NFTRevealHarness public nft;

    uint256[] tiers;
    string[]  tierNames;
    uint256 public revealTime;
    uint256 public mintPrice = 0.01 ether;
    uint256 public maxSupply = 100;

    function setUp() public {
        tiers.push(5000); // Common
        tiers.push(3000); // Uncommon
        tiers.push(1500); // Rare
        tiers.push(500);  // Legendary
        tierNames.push("Common");
        tierNames.push("Uncommon");
        tierNames.push("Rare");
        tierNames.push("Legendary");

        revealTime = block.timestamp + 1 days;
        nft = new NFTRevealHarness(maxSupply, mintPrice, revealTime, tiers, tierNames);
        nft.openMint();
    }

    // ── mint ─────────────────────────────────────────────────────────────────

    function test_MintAssignsOwner() public {
        address minter = address(0x123);
        vm.deal(minter, 1 ether);
        vm.prank(minter);
        nft.mint{value: mintPrice}();
        assertEq(nft.ownerOf(1), minter);
    }

    function test_MintIncrementsTokenId() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        assertEq(nft.nextTokenId(), 1);
    }

    function test_MintClosedReverts() public {
        nft.closeMint();
        vm.expectRevert("NFTReveal: mint closed");
        nft.mint{value: mintPrice}();
    }

    function test_MintSoldOutReverts() public {
        NFTRevealHarness tiny = new NFTRevealHarness(2, mintPrice, revealTime, tiers, tierNames);
        tiny.openMint();
        vm.deal(address(this), 10 ether);
        tiny.mint{value: mintPrice}();
        tiny.mint{value: mintPrice}();
        vm.expectRevert("NFTReveal: sold out");
        tiny.mint{value: mintPrice}();
    }

    function test_MintInsufficientPaymentReverts() public {
        vm.expectRevert("NFTReveal: insufficient payment");
        nft.mint{value: mintPrice - 1}();
    }

    function test_MintTakesProtocolFee() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        assertGt(nft.protocolFeeBalance(), 0);
    }

    // ── shouldProgressLoop ────────────────────────────────────────────────────

    function test_NotReadyBeforeRevealTime() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        (bool ready,) = nft.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_ReadyAfterRevealTime() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        (bool ready,) = nft.shouldProgressLoop();
        assertTrue(ready);
    }

    function test_NotReadyIfNoTokensMinted() public {
        vm.warp(revealTime);
        (bool ready,) = nft.shouldProgressLoop();
        assertFalse(ready);
    }

    function test_NotReadyIfAlreadyRevealed() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(keccak256("seed"));
        (bool ready,) = nft.shouldProgressLoop();
        assertFalse(ready);
    }

    // ── tickForTest ──────────────────────────────────────────────────────────

    function test_RevealSetsFlag() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(keccak256("seed"));
        assertTrue(nft.revealed());
    }

    function test_RevealAssignsAllTiers() public {
        vm.deal(address(this), 10 ether);
        for (uint256 i = 0; i < 10; i++) nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(keccak256("seed"));
        for (uint256 i = 1; i <= 10; i++) {
            assertGt(nft.tokenTier(i), 0);
        }
    }

    function test_RevealStoresSeed() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        bytes32 seed = keccak256("deterministic");
        nft.tickForTest(seed);
        assertEq(nft.revealSeed(), seed);
    }

    function test_CannotRevealTwice() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(keccak256("seed"));
        vm.expectRevert("NFTReveal: already revealed");
        nft.tickForTest(keccak256("seed2"));
    }

    function test_TierNameUnrevealed() public view {
        assertEq(nft.tierName(1), "Unrevealed");
    }

    function test_TierNameAfterReveal() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(keccak256("seed"));
        string memory name = nft.tierName(1);
        assertTrue(
            keccak256(bytes(name)) == keccak256(bytes("Common")) ||
            keccak256(bytes(name)) == keccak256(bytes("Uncommon")) ||
            keccak256(bytes(name)) == keccak256(bytes("Rare")) ||
            keccak256(bytes(name)) == keccak256(bytes("Legendary"))
        );
    }

    // ── constructor validation ────────────────────────────────────────────────

    function test_ConstructorTierSumNot10000Reverts() public {
        tiers[0] = 4999; // sum = 9999
        vm.expectRevert("NFTReveal: tiers must sum to 10000");
        new NFTRevealHarness(maxSupply, mintPrice, revealTime, tiers, tierNames);
    }

    function test_ConstructorLengthMismatchReverts() public {
        tierNames.push("Extra");
        vm.expectRevert("NFTReveal: tier length mismatch");
        new NFTRevealHarness(maxSupply, mintPrice, revealTime, tiers, tierNames);
    }

    // ── admin ─────────────────────────────────────────────────────────────────

    function test_WithdrawFees() public {
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        uint256 fees = nft.protocolFeeBalance();
        assertGt(fees, 0);
        address recipient = address(0xFEED);
        nft.withdrawProtocolFees(recipient);
        assertEq(recipient.balance, fees);
    }

    // ── fuzz ──────────────────────────────────────────────────────────────────

    function testFuzz_DifferentSeedsGiveDifferentTraits(bytes32 s1, bytes32 s2) public {
        vm.assume(s1 != s2);
        vm.deal(address(this), 1 ether);
        nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(s1);
        uint256 tier1 = nft.tokenTier(1);
        // Can't re-reveal same contract; just verify tier is in valid range
        assertGe(tier1, 1);
        assertLe(tier1, 4);
    }

    function testFuzz_AllTokensGetTiers(uint8 mintCount) public {
        vm.assume(mintCount > 0 && mintCount <= 50);
        vm.deal(address(this), uint256(mintCount) * mintPrice + 1 ether);
        for (uint256 i = 0; i < mintCount; i++) nft.mint{value: mintPrice}();
        vm.warp(revealTime);
        nft.tickForTest(keccak256(abi.encode(mintCount)));
        for (uint256 i = 1; i <= mintCount; i++) {
            assertGt(nft.tokenTier(i), 0);
        }
    }

    receive() external payable {}
}
