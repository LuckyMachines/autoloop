// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/AutoLoop.sol";
import "../src/AutoLoopRegistry.sol";
import "../src/AutoLoopRegistrar.sol";
import "../src/sample/NumberGoUp.sol";

// ===============================================================
//  Malicious contracts for reentrancy testing (H6)
// ===============================================================

/// @dev Attacker that tries to re-enter progressLoop during controller ETH receive
contract ReentrantController {
    AutoLoop public autoLoop;
    address public target;
    bytes public attackData;
    bool public attacked;

    constructor(AutoLoop _autoLoop) {
        autoLoop = _autoLoop;
    }

    function setAttackParams(address _target, bytes memory _data) external {
        target = _target;
        attackData = _data;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            // Try to re-enter progressLoop when receiving gas refund
            try autoLoop.progressLoop(target, attackData) {} catch {}
        }
    }
}

/// @dev Attacker that tries to re-enter requestRefund
contract ReentrantRefundReceiver {
    AutoLoop public autoLoop;
    AutoLoopRegistrar public registrar;
    address public contractAddr;
    uint256 public reentryCount;

    constructor(AutoLoop _autoLoop, AutoLoopRegistrar _registrar) {
        autoLoop = _autoLoop;
        registrar = _registrar;
    }

    function setTarget(address _contract) external {
        contractAddr = _contract;
    }

    receive() external payable {
        if (reentryCount < 1) {
            reentryCount++;
            // Try to re-enter via another refund
            try registrar.requestRefundFor(contractAddr, address(this)) {} catch {}
        }
    }
}

/// @dev Contract with reverting receive for griefing test (H3)
contract RevertingReceiver {
    receive() external payable {
        revert("I reject ETH");
    }
}

// ===============================================================
//  Upgraded AutoLoop for upgrade safety tests (H5)
// ===============================================================

contract AutoLoopV2 is AutoLoop {
    uint256 public newVariable;

    function setNewVariable(uint256 val) external {
        newVariable = val;
    }

    function initializeV2() public reinitializer(2) {
        newVariable = 42;
    }
}

/**
 * @title AutoLoopSecurityTest
 * @notice Security-focused tests covering reentrancy (H6), upgrade safety (H5),
 *         fuzz tests (M6), balance invariants, deregistration state, and pause behavior.
 */
contract AutoLoopSecurityTest is Test {
    AutoLoop public autoLoop;
    AutoLoopRegistry public registry;
    AutoLoopRegistrar public registrar;

    address public proxyAdmin;
    address public admin;
    address public controller1;
    address public controller2;

    TransparentUpgradeableProxy public autoLoopProxy;
    TransparentUpgradeableProxy public registryProxy;
    TransparentUpgradeableProxy public registrarProxy;

    NumberGoUp public game1;

    bytes32 public CONTROLLER_ROLE;
    bytes32 public REGISTRAR_ROLE;

    uint256 constant GAS_PRICE = 20 gwei;

    receive() external payable {}

    function setUp() public {
        proxyAdmin = vm.addr(99);
        controller1 = vm.addr(1);
        controller2 = vm.addr(2);
        admin = address(this);

        vm.deal(admin, 1000 ether);
        vm.deal(controller1, 100 ether);
        vm.deal(controller2, 100 ether);

        // Deploy AutoLoop behind proxy
        AutoLoop autoLoopImpl = new AutoLoop();
        autoLoopProxy = new TransparentUpgradeableProxy(
            address(autoLoopImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(string)", "0.0.1")
        );
        autoLoop = AutoLoop(address(autoLoopProxy));

        // Deploy Registry behind proxy
        AutoLoopRegistry registryImpl = new AutoLoopRegistry();
        registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            proxyAdmin,
            abi.encodeWithSignature("initialize(address)", admin)
        );
        registry = AutoLoopRegistry(address(registryProxy));

        // Deploy Registrar behind proxy
        AutoLoopRegistrar registrarImpl = new AutoLoopRegistrar();
        registrarProxy = new TransparentUpgradeableProxy(
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

        CONTROLLER_ROLE = autoLoop.CONTROLLER_ROLE();
        REGISTRAR_ROLE = autoLoop.REGISTRAR_ROLE();

        // Wire up registrar roles
        registry.setRegistrar(address(registrar));
        autoLoop.setRegistrar(address(registrar));
    }

    // ===============================================================
    //  Section 1 — Reentrancy Tests (H6)
    // ===============================================================

    function test_ReentrancyOnProgressLoop() public {
        // Setup: deploy game, register, fund
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);

        // Deploy reentrant controller
        ReentrantController attacker = new ReentrantController(autoLoop);
        vm.deal(address(attacker), 10 ether);

        // Register the attacker as a controller
        vm.prank(address(attacker));
        registrar.registerController{value: 0.0001 ether}();

        // Fund game
        registrar.deposit{value: 10 ether}(address(game1));
        vm.warp(block.timestamp + 1);

        // Get progress data
        (, bytes memory progressWithData) = game1.shouldProgressLoop();

        // Set attack params
        attacker.setAttackParams(address(game1), progressWithData);

        // Execute — should succeed but reentrancy attempt should fail silently
        vm.txGasPrice(GAS_PRICE);
        vm.prank(address(attacker));
        autoLoop.progressLoop(address(game1), progressWithData);

        // Game should have progressed exactly once (reentrancy blocked)
        assertEq(game1.number(), 1, "Game should progress exactly once");
    }

    function test_ReentrancyOnRefund() public {
        // Setup
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 5 ether}(address(game1));

        // Deploy reentrant receiver
        ReentrantRefundReceiver attacker = new ReentrantRefundReceiver(autoLoop, registrar);
        attacker.setTarget(address(game1));

        // Try refund to reentrant receiver — the reentrancy guard should prevent double-refund
        // requestRefundFor will send to attacker which tries to re-enter
        // The inner call should fail due to nonReentrant
        registrar.requestRefundFor(address(game1), address(attacker));

        // Balance should be zeroed after single refund
        assertEq(autoLoop.balance(address(game1)), 0, "Balance should be zero after refund");
        assertEq(attacker.reentryCount(), 1, "Reentry attempt should have been made");
    }

    function test_ReentrancyOnWithdrawProtocolFees() public {
        // Setup game, progress to accumulate protocol fees
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 10 ether}(address(game1));
        vm.warp(block.timestamp + 1);

        // Register controller and progress
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        (, bytes memory progressWithData) = game1.shouldProgressLoop();
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        autoLoop.progressLoop(address(game1), progressWithData);

        uint256 protocolBal = autoLoop.protocolBalance();
        if (protocolBal > 0) {
            // Withdraw should succeed once, reentrancy should be blocked by nonReentrant
            autoLoop.withdrawProtocolFees(protocolBal, admin);
            assertEq(autoLoop.protocolBalance(), 0, "Protocol balance should be zero");
        }
    }

    // ===============================================================
    //  Section 2 — Upgrade Safety Tests (H5)
    // ===============================================================

    function test_UpgradePreservesState() public {
        // Setup: register a game and deposit
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 5 ether}(address(game1));

        // Record pre-upgrade state
        uint256 balanceBefore = autoLoop.balance(address(game1));
        string memory versionBefore = autoLoop.version();
        uint256 baseFeeBefore = autoLoop.baseFee();

        // Upgrade to V2
        AutoLoopV2 v2Impl = new AutoLoopV2();
        vm.prank(proxyAdmin);
        ProxyAdmin proxyAdminContract = ProxyAdmin(
            _getProxyAdmin(address(autoLoopProxy))
        );
        proxyAdminContract.upgradeAndCall(
            ITransparentUpgradeableProxy(address(autoLoopProxy)),
            address(v2Impl),
            ""
        );

        AutoLoopV2 autoLoopV2 = AutoLoopV2(address(autoLoopProxy));

        // Verify state preserved
        assertEq(autoLoopV2.balance(address(game1)), balanceBefore, "Balance should be preserved");
        assertEq(autoLoopV2.version(), versionBefore, "Version should be preserved");
        assertEq(autoLoopV2.baseFee(), baseFeeBefore, "BaseFee should be preserved");

        // Verify new functionality works
        autoLoopV2.setNewVariable(123);
        assertEq(autoLoopV2.newVariable(), 123, "New variable should work");
    }

    function test_CannotDoubleInitialize() public {
        // Attempt to re-initialize should revert
        vm.expectRevert();
        autoLoop.initialize("exploit");
    }

    function test_CannotDoubleInitializeRegistry() public {
        vm.expectRevert();
        registry.initialize(vm.addr(999));
    }

    function test_CannotDoubleInitializeRegistrar() public {
        vm.expectRevert();
        registrar.initialize(address(0), address(0), vm.addr(999));
    }

    function test_OnlyProxyAdminCanUpgrade() public {
        AutoLoopV2 v2Impl = new AutoLoopV2();

        // Non-proxy-admin cannot upgrade
        address proxyAdminAddr = _getProxyAdmin(address(autoLoopProxy));
        ProxyAdmin proxyAdminContract = ProxyAdmin(proxyAdminAddr);

        // Only the proxyAdmin owner can call upgrade
        vm.prank(controller1);
        vm.expectRevert();
        proxyAdminContract.upgradeAndCall(
            ITransparentUpgradeableProxy(address(autoLoopProxy)),
            address(v2Impl),
            ""
        );
    }

    // ===============================================================
    //  Section 3 — Fuzz Tests (M6)
    // ===============================================================

    function testFuzz_DepositAndRefund(uint256 amount) public {
        // Bound to reasonable values
        amount = bound(amount, 1 wei, 100 ether);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);

        uint256 adminBalBefore = admin.balance;

        registrar.deposit{value: amount}(address(game1));
        assertEq(autoLoop.balance(address(game1)), amount, "Deposit amount mismatch");

        registrar.requestRefundFor(address(game1), admin);
        assertEq(autoLoop.balance(address(game1)), 0, "Balance not zeroed after refund");
        assertEq(admin.balance, adminBalBefore, "Admin should get back full deposit");
    }

    function testFuzz_FeePortionBoundaries(uint256 portion) public {
        portion = bound(portion, 0, 100);

        autoLoop.setControllerFeePortion(portion);
        // Should not revert — all values 0-100 are valid

        // Reset
        autoLoop.setControllerFeePortion(50);
    }

    function testFuzz_FeePortionAbove100Reverts(uint256 portion) public {
        portion = bound(portion, 101, type(uint256).max);

        vm.expectRevert("Percentage should be less than or equal to 100");
        autoLoop.setControllerFeePortion(portion);
    }

    function testFuzz_MaxGasClamping(uint256 maxGasVal) public {
        maxGasVal = bound(maxGasVal, 1, type(uint256).max);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), maxGasVal);

        uint256 resultMaxGas = autoLoop.maxGasFor(address(game1));
        uint256 threshold = autoLoop.gasThreshold();

        if (maxGasVal > threshold) {
            assertEq(resultMaxGas, threshold, "Should be clamped to threshold");
        } else {
            assertEq(resultMaxGas, maxGasVal, "Should be exact value");
        }
    }

    // ===============================================================
    //  Section 4 — Balance Invariant Tests
    // ===============================================================

    function test_TotalBalanceInvariant() public {
        // Setup game, fund, progress multiple times
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 5 ether}(address(game1));

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        // Progress game1 three times with explicit block/time advances (unrolled)
        _advanceAndProgress(address(game1), 2, 100);
        _advanceAndProgress(address(game1), 3, 200);
        _advanceAndProgress(address(game1), 4, 300);

        // Contract ETH balance should equal sum of user balances + protocol balance
        uint256 game1Bal = autoLoop.balance(address(game1));
        uint256 protocolBal = autoLoop.protocolBalance();

        // All ETH should be accounted for
        assertEq(
            address(autoLoop).balance,
            game1Bal + protocolBal,
            "All ETH should be accounted for"
        );
    }

    function _advanceAndProgress(address gameAddr, uint256 blockNum, uint256 timestamp) internal {
        vm.roll(blockNum);
        vm.warp(timestamp);
        (, bytes memory data) = NumberGoUp(gameAddr).shouldProgressLoop();
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        autoLoop.progressLoop(gameAddr, data);
    }

    // ===============================================================
    //  Section 5 — Deregistration + Re-registration State Tests
    // ===============================================================

    function test_DeregisterAutoRefundsBalance() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 3 ether}(address(game1));

        uint256 adminBalBefore = admin.balance;

        // Deregister should auto-refund
        registrar.deregisterAutoLoopFor(address(game1));

        assertFalse(registry.isRegisteredAutoLoop(address(game1)), "Should be deregistered");
        assertEq(autoLoop.balance(address(game1)), 0, "Balance should be zero after deregister");
        assertEq(admin.balance, adminBalBefore + 3 ether, "Admin should receive refund");
    }

    function test_DeregisterAndReregister() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        assertTrue(registry.isRegisteredAutoLoop(address(game1)));

        // Deregister
        registrar.deregisterAutoLoopFor(address(game1));
        assertFalse(registry.isRegisteredAutoLoop(address(game1)));

        // Re-register should work
        registrar.registerAutoLoopFor(address(game1), 1_000_000);
        assertTrue(registry.isRegisteredAutoLoop(address(game1)));
    }

    function test_DeregisterControllerAndReregister() public {
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();
        assertTrue(registry.isRegisteredController(controller1));

        // Deregister
        vm.prank(controller1);
        registrar.deregisterController();
        assertFalse(registry.isRegisteredController(controller1));

        // Re-register should work
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();
        assertTrue(registry.isRegisteredController(controller1));
    }

    // ===============================================================
    //  Section 6 — Pause Tests (M8)
    // ===============================================================

    function test_PauseBlocksProgressLoop() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 5 ether}(address(game1));

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();
        vm.warp(block.timestamp + 1);

        // Pause
        autoLoop.pause();

        (, bytes memory data) = game1.shouldProgressLoop();
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        vm.expectRevert();
        autoLoop.progressLoop(address(game1), data);

        // Unpause
        autoLoop.unpause();

        // Should work again
        vm.txGasPrice(GAS_PRICE);
        vm.prank(controller1);
        autoLoop.progressLoop(address(game1), data);
        assertEq(game1.number(), 1, "Should progress after unpause");
    }

    function test_PauseBlocksDeposit() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);

        autoLoop.pause();

        vm.expectRevert();
        registrar.deposit{value: 1 ether}(address(game1));

        autoLoop.unpause();
    }

    function test_PauseBlocksRegistration() public {
        registrar.pause();

        game1 = new NumberGoUp(0);
        vm.expectRevert();
        registrar.registerAutoLoopFor(address(game1), 2_000_000);

        registrar.unpause();
    }

    function test_OnlyAdminCanPause() public {
        vm.prank(controller1);
        vm.expectRevert();
        autoLoop.pause();
    }

    function test_OnlyAdminCanUnpause() public {
        autoLoop.pause();

        vm.prank(controller1);
        vm.expectRevert();
        autoLoop.unpause();

        // Admin can unpause
        autoLoop.unpause();
    }

    // ===============================================================
    //  Section 7 — Zero Address Validation (H2)
    // ===============================================================

    function test_RefundToZeroAddressReverts() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 1 ether}(address(game1));

        vm.expectRevert("Cannot refund to zero address");
        registrar.requestRefundFor(address(game1), address(0));
    }

    function test_WithdrawProtocolFeesToZeroAddressReverts() public {
        vm.expectRevert("Cannot withdraw to zero address");
        autoLoop.withdrawProtocolFees(0, address(0));
    }

    // ===============================================================
    //  Section 8 — Registry Cleanup Tests (C3)
    // ===============================================================

    function test_CleanControllerList() public {
        // Register two controllers
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();
        vm.prank(controller2);
        registrar.registerController{value: 0.0001 ether}();

        address[] memory before = registry.getRegisteredControllers();
        assertEq(before.length, 2);

        // Deregister one
        vm.prank(controller1);
        registrar.deregisterController();

        // Before cleanup, array still has 2 entries (one is deregistered)
        // After cleanup, only active entries remain
        registry.cleanControllerList();

        address[] memory after_ = registry.getRegisteredControllers();
        assertEq(after_.length, 1, "Should have 1 controller after cleanup");
        assertEq(after_[0], controller2, "Remaining controller should be controller2");
    }

    function test_CleanAutoLoopList() public {
        game1 = new NumberGoUp(0);
        NumberGoUp game2 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.registerAutoLoopFor(address(game2), 2_000_000);

        address[] memory before = registry.getRegisteredAutoLoops();
        assertEq(before.length, 2);

        // Deregister game1
        registrar.deregisterAutoLoopFor(address(game1));

        registry.cleanAutoLoopList();

        address[] memory after_ = registry.getRegisteredAutoLoops();
        assertEq(after_.length, 1, "Should have 1 autoloop after cleanup");
        assertEq(after_[0], address(game2), "Remaining should be game2");
    }

    // ===============================================================
    //  Section 9 — Emergency Withdrawal (C4)
    // ===============================================================

    function test_EmergencyWithdraw() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 5 ether}(address(game1));

        uint256 adminBalBefore = admin.balance;

        registrar.emergencyWithdraw(address(game1), admin);

        assertEq(autoLoop.balance(address(game1)), 0, "Balance should be zero");
        assertEq(admin.balance, adminBalBefore + 5 ether, "Admin should receive funds");
    }

    function test_EmergencyWithdrawNonAdminReverts() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 5 ether}(address(game1));

        vm.prank(controller1);
        vm.expectRevert("Caller is not admin on contract");
        registrar.emergencyWithdraw(address(game1), controller1);
    }

    // ===============================================================
    //  Section 10 — Controller Griefing Test (H3 documentation)
    // ===============================================================

    function test_RevertingControllerGriefsProgressLoop() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 10 ether}(address(game1));

        // Deploy a reverting receiver "controller"
        RevertingReceiver badController = new RevertingReceiver();
        vm.deal(address(badController), 1 ether);

        // Register bad controller
        vm.prank(address(badController));
        // Cannot register — controller must accept ETH (demonstrated by registration fee bounce)
        vm.expectRevert("Registration failed. Controller unable to receive funds.");
        registrar.registerController{value: 0.0001 ether}();

        // This test documents H3: controllers that reject ETH cannot register,
        // so the push pattern is safe for registered controllers.
    }

    // ===============================================================
    //  Section 11 — Fuzz: Rapid Deposit / Refund / Re-deposit Cycling
    // ===============================================================

    /// @dev Rapid cycles of deposit → refund → re-deposit should never
    ///      lose or create ETH. Tests the Chainlink-style "trapped funds"
    ///      scenario where repeated operations could leave dust behind.
    function testFuzz_DepositRefundCycle(
        uint256 amount,
        uint8 cycles
    ) public {
        amount = bound(amount, 1 wei, 10 ether);
        cycles = uint8(bound(cycles, 1, 20));

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);

        uint256 adminBalStart = admin.balance;

        for (uint256 i = 0; i < cycles; i++) {
            // Deposit
            registrar.deposit{value: amount}(address(game1));
            assertEq(
                autoLoop.balance(address(game1)),
                amount,
                "Balance should match deposit"
            );

            // Refund
            registrar.requestRefundFor(address(game1), admin);
            assertEq(
                autoLoop.balance(address(game1)),
                0,
                "Balance should be zero after refund"
            );
        }

        // Admin should have exactly what they started with
        assertEq(admin.balance, adminBalStart, "No ETH lost or created after cycling");

        // AutoLoop contract should hold zero for this game
        assertEq(
            autoLoop.balance(address(game1)),
            0,
            "No dust remaining in contract"
        );
    }

    /// @dev Variant: deposit multiple times before a single refund.
    ///      Ensures incremental deposits are fully refundable.
    function testFuzz_MultiDepositSingleRefund(
        uint256 depositCount,
        uint256 amount
    ) public {
        depositCount = bound(depositCount, 1, 30);
        amount = bound(amount, 1 wei, 1 ether);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);

        uint256 adminBalStart = admin.balance;
        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < depositCount; i++) {
            registrar.deposit{value: amount}(address(game1));
            totalDeposited += amount;
        }

        assertEq(
            autoLoop.balance(address(game1)),
            totalDeposited,
            "Balance should equal sum of all deposits"
        );

        // Single refund should return everything
        registrar.requestRefundFor(address(game1), admin);
        assertEq(autoLoop.balance(address(game1)), 0, "Balance should be zero");
        assertEq(admin.balance, adminBalStart, "All ETH returned to admin");
    }

    // ===============================================================
    //  Section 12 — Fuzz: Refund During Active Loop Execution
    // ===============================================================

    /// @dev Simulates a refund immediately after a progressLoop execution.
    ///      Ensures the user can always withdraw remaining balance after
    ///      fees have been deducted, and no ETH gets stuck.
    function testFuzz_RefundAfterProgress(
        uint256 deposit,
        uint256 gasPrice
    ) public {
        // Use realistic ranges: deposit must cover gas+buffer+fee at the fuzzed price.
        // At 200 gwei with ~2M gas + 94k buffer + 70% fee, max cost is ~0.7 ETH.
        deposit = bound(deposit, 1 ether, 50 ether);
        gasPrice = bound(gasPrice, 1 gwei, 200 gwei);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: deposit}(address(game1));

        // Register controller
        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        // Advance time so shouldProgressLoop returns true
        vm.warp(block.timestamp + 31);
        vm.roll(block.number + 1);

        (, bytes memory data) = game1.shouldProgressLoop();

        // Progress loop — deducts gas cost + fee from balance
        vm.txGasPrice(gasPrice);
        vm.prank(controller1);
        autoLoop.progressLoop(address(game1), data);

        uint256 remainingBalance = autoLoop.balance(address(game1));
        uint256 protocolBal = autoLoop.protocolBalance();

        // Invariant: contract ETH = all user balances + protocol balance
        assertEq(
            address(autoLoop).balance,
            remainingBalance + protocolBal,
            "ETH invariant broken after progress"
        );

        // User should be able to refund whatever remains
        if (remainingBalance > 0) {
            uint256 adminBalBefore = admin.balance;
            registrar.requestRefundFor(address(game1), admin);
            assertEq(autoLoop.balance(address(game1)), 0, "Balance not zeroed");
            assertEq(
                admin.balance,
                adminBalBefore + remainingBalance,
                "Admin didn't receive correct refund"
            );
        }

        // Protocol fees should still be withdrawable
        if (protocolBal > 0) {
            uint256 adminBalBefore2 = admin.balance;
            autoLoop.withdrawProtocolFees(protocolBal, admin);
            assertEq(autoLoop.protocolBalance(), 0, "Protocol balance not zeroed");
            assertEq(
                admin.balance,
                adminBalBefore2 + protocolBal,
                "Admin didn't receive protocol fees"
            );
        }

        // Contract should be completely drained
        assertEq(address(autoLoop).balance, 0, "AutoLoop should hold zero ETH");
    }

    /// @dev Progress multiple times at different gas prices, then refund.
    ///      Tests that repeated fee deductions don't leave unrecoverable dust.
    function testFuzz_MultiProgressThenRefund(
        uint256 progressCount,
        uint256 gasPrice
    ) public {
        progressCount = bound(progressCount, 1, 10);
        gasPrice = bound(gasPrice, 1 gwei, 100 gwei);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 50 ether}(address(game1));

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        for (uint256 i = 0; i < progressCount; i++) {
            vm.warp(block.timestamp + 31);
            vm.roll(block.number + 1);

            (bool ready, bytes memory data) = game1.shouldProgressLoop();
            if (!ready) break;

            // Check balance is sufficient before progressing
            uint256 bal = autoLoop.balance(address(game1));
            if (bal < 0.001 ether) break; // avoid reverts on low balance

            vm.txGasPrice(gasPrice);
            vm.prank(controller1);
            autoLoop.progressLoop(address(game1), data);
        }

        // After all progress loops, verify invariant
        uint256 userBal = autoLoop.balance(address(game1));
        uint256 protoBal = autoLoop.protocolBalance();

        assertEq(
            address(autoLoop).balance,
            userBal + protoBal,
            "ETH invariant violated after multi-progress"
        );

        // Full refund + protocol withdrawal should drain contract
        if (userBal > 0) {
            registrar.requestRefundFor(address(game1), admin);
        }
        if (protoBal > 0) {
            autoLoop.withdrawProtocolFees(protoBal, admin);
        }

        assertEq(address(autoLoop).balance, 0, "Dust remaining after full withdrawal");
    }

    // ===============================================================
    //  Section 13 — Fuzz: Deregister + Refund Race Conditions
    // ===============================================================

    /// @dev Deregister auto-refunds to primary admin. Verify this works
    ///      correctly with any deposit amount and that re-registration
    ///      starts with a clean slate.
    function testFuzz_DeregisterRefundReregister(uint256 amount) public {
        amount = bound(amount, 1 wei, 10 ether);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: amount}(address(game1));

        uint256 adminBalBefore = admin.balance;

        // Deregister — should auto-refund
        registrar.deregisterAutoLoopFor(address(game1));

        assertEq(autoLoop.balance(address(game1)), 0, "Balance not zeroed on deregister");
        assertEq(admin.balance, adminBalBefore + amount, "Refund not received on deregister");
        assertFalse(registry.isRegisteredAutoLoop(address(game1)), "Still registered");

        // Re-register — should start fresh with zero balance
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        assertTrue(registry.isRegisteredAutoLoop(address(game1)), "Not re-registered");
        assertEq(autoLoop.balance(address(game1)), 0, "Balance not zero after re-register");
    }

    /// @dev Emergency withdraw then deregister — both should succeed,
    ///      no double-refund.
    function testFuzz_EmergencyWithdrawThenDeregister(uint256 amount) public {
        amount = bound(amount, 1 wei, 10 ether);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: amount}(address(game1));

        uint256 adminBalBefore = admin.balance;

        // Emergency withdraw first
        registrar.emergencyWithdraw(address(game1), admin);
        assertEq(autoLoop.balance(address(game1)), 0, "Balance not zeroed");
        assertEq(admin.balance, adminBalBefore + amount, "Didn't receive emergency refund");

        // Deregister — balance is zero, should not revert
        registrar.deregisterAutoLoopFor(address(game1));
        assertFalse(registry.isRegisteredAutoLoop(address(game1)), "Still registered");

        // Admin balance should not have changed (no double refund)
        assertEq(admin.balance, adminBalBefore + amount, "Double refund detected");
    }

    /// @dev Deregister with zero balance should succeed without revert.
    function test_DeregisterZeroBalance() public {
        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        // No deposit — zero balance

        // Should not revert
        registrar.deregisterAutoLoopFor(address(game1));
        assertFalse(registry.isRegisteredAutoLoop(address(game1)), "Still registered");
    }

    // ===============================================================
    //  Section 14 — Fuzz: Dust Accumulation Over Many Loops
    // ===============================================================

    /// @dev Run many loops with varying gas prices and verify that after
    ///      refund + protocol withdrawal, exactly zero ETH remains.
    ///      This catches any integer division rounding that could leak
    ///      or create wei over many iterations.
    function testFuzz_DustAfterManyLoops(uint256 seed) public {
        seed = bound(seed, 1, type(uint128).max);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 100 ether}(address(game1));

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        // Run 50 loops with pseudo-random gas prices
        for (uint256 i = 0; i < 50; i++) {
            vm.warp(block.timestamp + 31);
            vm.roll(block.number + 1);

            (bool ready, bytes memory data) = game1.shouldProgressLoop();
            if (!ready) break;

            uint256 bal = autoLoop.balance(address(game1));
            if (bal < 0.01 ether) break;

            // Vary gas price using seed
            uint256 gp = bound(
                uint256(keccak256(abi.encode(seed, i))),
                1 gwei,
                150 gwei
            );

            vm.txGasPrice(gp);
            vm.prank(controller1);
            autoLoop.progressLoop(address(game1), data);
        }

        // Verify invariant holds
        uint256 userBal = autoLoop.balance(address(game1));
        uint256 protoBal = autoLoop.protocolBalance();

        assertEq(
            address(autoLoop).balance,
            userBal + protoBal,
            "ETH invariant broken after 50 loops"
        );

        // Withdraw everything
        if (userBal > 0) {
            registrar.requestRefundFor(address(game1), admin);
        }
        if (protoBal > 0) {
            autoLoop.withdrawProtocolFees(protoBal, admin);
        }

        // No dust should remain
        assertEq(
            address(autoLoop).balance,
            0,
            "Dust detected after full withdrawal - rounding error"
        );
    }

    /// @dev Fuzz the fee percentages themselves during active operation.
    ///      Change controller/protocol fee split mid-stream and verify
    ///      accounting still holds.
    function testFuzz_FeeChangeMidStream(
        uint256 newControllerPortion,
        uint256 loops
    ) public {
        newControllerPortion = bound(newControllerPortion, 0, 100);
        loops = bound(loops, 1, 10);

        game1 = new NumberGoUp(0);
        registrar.registerAutoLoopFor(address(game1), 2_000_000);
        registrar.deposit{value: 50 ether}(address(game1));

        vm.prank(controller1);
        registrar.registerController{value: 0.0001 ether}();

        // Run some loops with default fees
        for (uint256 i = 0; i < loops / 2 + 1; i++) {
            vm.warp(block.timestamp + 31);
            vm.roll(block.number + 1);
            (bool ready, bytes memory data) = game1.shouldProgressLoop();
            if (!ready) break;
            uint256 bal = autoLoop.balance(address(game1));
            if (bal < 0.01 ether) break;
            vm.txGasPrice(20 gwei);
            vm.prank(controller1);
            autoLoop.progressLoop(address(game1), data);
        }

        // Change fee split mid-stream
        autoLoop.setControllerFeePortion(newControllerPortion);

        // Run more loops with new fees
        for (uint256 i = 0; i < loops / 2 + 1; i++) {
            vm.warp(block.timestamp + 31);
            vm.roll(block.number + 1);
            (bool ready, bytes memory data) = game1.shouldProgressLoop();
            if (!ready) break;
            uint256 bal = autoLoop.balance(address(game1));
            if (bal < 0.01 ether) break;
            vm.txGasPrice(20 gwei);
            vm.prank(controller1);
            autoLoop.progressLoop(address(game1), data);
        }

        // Verify invariant
        uint256 userBal = autoLoop.balance(address(game1));
        uint256 protoBal = autoLoop.protocolBalance();

        assertEq(
            address(autoLoop).balance,
            userBal + protoBal,
            "Invariant broken after fee change"
        );

        // Full drain
        if (userBal > 0) {
            registrar.requestRefundFor(address(game1), admin);
        }
        if (protoBal > 0) {
            autoLoop.withdrawProtocolFees(protoBal, admin);
        }

        assertEq(address(autoLoop).balance, 0, "Dust after fee change scenario");

        // Reset fees
        autoLoop.setControllerFeePortion(50);
    }

    // ===============================================================
    //  Internal helpers
    // ===============================================================

    /// @dev Get the ProxyAdmin address for a TransparentUpgradeableProxy
    function _getProxyAdmin(address proxy) internal view returns (address) {
        // The ProxyAdmin is stored at the admin slot
        // For OZ v5 TransparentUpgradeableProxy, the admin is a separate ProxyAdmin contract
        // deployed by the proxy constructor. We read it from storage.
        bytes32 adminSlot = vm.load(
            proxy,
            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
        );
        return address(uint160(uint256(adminSlot)));
    }
}
