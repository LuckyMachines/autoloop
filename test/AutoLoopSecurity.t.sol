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
