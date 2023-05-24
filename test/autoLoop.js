const { assert, expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");
const exp = require("constants");

describe("Auto Loop", function () {
  // Accounts
  let ACCOUNTS;
  let ADMIN;
  let CONTROLLER;
  let CONTROLLER_SIGNER;
  let ADMIN_2;
  let ADMIN_2_SIGNER;

  // Contract Factories
  let AUTO_LOOP;
  let AUTO_LOOP_VIA_CONTROLLER;
  let AUTO_LOOP_REGISTRY;
  let AUTO_LOOP_REGISTRAR;
  let SAMPLE_GAME; // ADMIN's game
  let SAMPLE_GAME_2; // ADMIN_2's game

  // Access Roles
  let CONTROLLER_ROLE;
  let REGISTRY_ROLE;
  let REGISTRAR_ROLE;

  let Game;

  before(async function () {
    let tx;
    let receipt;

    ACCOUNTS = await ethers.provider.listAccounts();
    console.log("Accounts:", ACCOUNTS);
    ADMIN = ACCOUNTS[0];
    CONTROLLER = ACCOUNTS[1];
    CONTROLLER_SIGNER = ethers.provider.getSigner(ACCOUNTS[1]);
    ADMIN_2 = ACCOUNTS[2];
    ADMIN_2_SIGNER = ethers.provider.getSigner(ACCOUNTS[2]);

    Game = await hre.ethers.getContractFactory("NumberGoUp");

    const AutoLoop = await hre.ethers.getContractFactory("AutoLoop");
    const AutoLoopRegistry = await hre.ethers.getContractFactory(
      "AutoLoopRegistry"
    );
    const AutoLoopRegistrar = await hre.ethers.getContractFactory(
      "AutoLoopRegistrar"
    );

    // AutoLoop
    console.log("Deploying Auto Loop...");
    AUTO_LOOP = await AutoLoop.deploy();
    await AUTO_LOOP.deployed();
    console.log("Auto Loop deployed to", AUTO_LOOP.address);

    // AutoLoopRegistry
    AUTO_LOOP_REGISTRY = await AutoLoopRegistry.deploy(ADMIN);
    await AUTO_LOOP_REGISTRY.deployed();
    console.log("Registry deployed to", AUTO_LOOP_REGISTRY.address);

    // AutoLoopRegistrar
    AUTO_LOOP_REGISTRAR = await AutoLoopRegistrar.deploy(
      AUTO_LOOP.address,
      AUTO_LOOP_REGISTRY.address,
      ADMIN
    );
    await AUTO_LOOP_REGISTRAR.deployed();
    console.log("Registrar deployed to", AUTO_LOOP_REGISTRAR.address);

    console.log("Getting access roles");
    CONTROLLER_ROLE = await AUTO_LOOP.CONTROLLER_ROLE();
    REGISTRY_ROLE = await AUTO_LOOP.REGISTRY_ROLE();
    REGISTRAR_ROLE = await AUTO_LOOP.REGISTRAR_ROLE();
    console.log("Controller role:", CONTROLLER_ROLE);
  });

  describe("Registration + Admin", function () {
    it("Sets registrar", async function () {
      tx = await AUTO_LOOP_REGISTRY.setRegistrar(AUTO_LOOP_REGISTRAR.address);
      await tx.wait();
      let hasRegistrarRole = await AUTO_LOOP_REGISTRY.hasRole(
        REGISTRAR_ROLE,
        AUTO_LOOP_REGISTRAR.address
      );
      expect(hasRegistrarRole).to.equal(true);

      tx = await AUTO_LOOP.setRegistrar(AUTO_LOOP_REGISTRAR.address);
      await tx.wait();
      hasRegistrarRole = await AUTO_LOOP.hasRole(
        REGISTRAR_ROLE,
        AUTO_LOOP_REGISTRAR.address
      );
      expect(hasRegistrarRole).to.equal(true);
    });
    it("Registers AutoLoop compatible interface", async function () {
      const updateInterval = 1;
      SAMPLE_GAME = await Game.deploy(updateInterval);
      await SAMPLE_GAME.deployed();
      let isRegistered = await AUTO_LOOP_REGISTRY.isRegisteredAutoLoop(
        SAMPLE_GAME.address
      );
      expect(isRegistered).to.equal(false);
      const canRegister = await AUTO_LOOP_REGISTRAR.canRegisterAutoLoop(
        ADMIN,
        SAMPLE_GAME.address
      );
      expect(canRegister).to.equal(true);
      tx = await AUTO_LOOP_REGISTRAR.registerAutoLoopFor(
        SAMPLE_GAME.address,
        "2000000"
      );
      await tx.wait();
      isRegistered = await AUTO_LOOP_REGISTRY.isRegisteredAutoLoop(
        SAMPLE_GAME.address
      );
      expect(isRegistered).to.equal(true);
    });
    it("Registers Controller", async function () {
      const registrarArtifact = require("../artifacts/contracts/AutoLoopRegistrar.sol/AutoLoopRegistrar.json");
      const registrarViaController = new ethers.Contract(
        AUTO_LOOP_REGISTRAR.address,
        registrarArtifact.abi,
        CONTROLLER_SIGNER
      );
      let isRegistered = await AUTO_LOOP_REGISTRY.isRegisteredController(
        CONTROLLER
      );
      expect(isRegistered).to.equal(false);

      const canRegister = await AUTO_LOOP_REGISTRAR.canRegisterController(
        CONTROLLER
      );
      expect(canRegister).to.equal(true);

      tx = await registrarViaController.registerController();
      await tx.wait();
      isRegistered = await AUTO_LOOP_REGISTRY.isRegisteredController(
        CONTROLLER
      );
      expect(isRegistered).to.equal(true);

      AUTO_LOOP_VIA_CONTROLLER = AUTO_LOOP.connect(CONTROLLER_SIGNER);
    });
    it("Safe transfers ALCC", async function () {
      const updateInterval = 1;
      SAMPLE_GAME_2 = await Game.deploy(updateInterval);
      await SAMPLE_GAME_2.deployed();
      console.log("Admin2 address:", ADMIN_2);
      tx = await SAMPLE_GAME_2.safeTransferAdmin(ADMIN_2);
      await tx.wait();
      let canRegister = await AUTO_LOOP_REGISTRAR.canRegisterAutoLoop(
        ADMIN,
        SAMPLE_GAME_2.address
      );
      expect(canRegister).to.equal(true);
      canRegister = await AUTO_LOOP_REGISTRAR.canRegisterAutoLoop(
        ADMIN_2,
        SAMPLE_GAME_2.address
      );
      expect(canRegister).to.equal(false);
      SAMPLE_GAME_2 = SAMPLE_GAME_2.connect(ADMIN_2_SIGNER);
      tx = await SAMPLE_GAME_2.acceptTransferAdminRequest();
      await tx.wait();
      canRegister = await AUTO_LOOP_REGISTRAR.canRegisterAutoLoop(
        ADMIN_2,
        SAMPLE_GAME_2.address
      );
      expect(canRegister).to.equal(true);
      canRegister = await AUTO_LOOP_REGISTRAR.canRegisterAutoLoop(
        ADMIN,
        SAMPLE_GAME_2.address
      );
      expect(canRegister).to.equal(false);
    });
    it("Returns list of all registered contracts", async function () {
      tx = await AUTO_LOOP_REGISTRAR.registerAutoLoopFor(
        SAMPLE_GAME_2.address,
        "2000000"
      );
      await tx.wait();
      const allContracts = await AUTO_LOOP_REGISTRY.getRegisteredAutoLoops();
      console.log("All registered autoloops:", allContracts);
      expect(allContracts).to.contain.members([SAMPLE_GAME.address]);
    });
    it("Returns list of admin registered contracts", async function () {
      const adminRegisteredContracts =
        await AUTO_LOOP_REGISTRY.getRegisteredAutoLoopsFor(ADMIN);
      console.log("Admin registered AutoLoops:", adminRegisteredContracts);
      const adminRegisteredLoopIndices =
        await AUTO_LOOP_REGISTRY.getRegisteredAutoLoopIndicesFor(ADMIN);
      console.log("Admin registered indices:", adminRegisteredLoopIndices);
    });
  });
  describe("Controller + Updates", function () {
    it("ALCI wants update", async function () {
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      expect(shouldProgress.loopIsReady).to.equal(true);
    });
    it("Underfunded contract cannot progress loop", async function () {
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      await expect(
        AUTO_LOOP_VIA_CONTROLLER.progressLoop(
          SAMPLE_GAME.address,
          shouldProgress.progressWithData
        )
      ).to.be.revertedWith(
        "AutoLoop compatible contract balance too low to run update + fee."
      );
    });
    it("ALCI can fund contract", async function () {
      const contractBalanceBefore = await AUTO_LOOP.balance(
        SAMPLE_GAME.address
      );
      await AUTO_LOOP_REGISTRAR.deposit(SAMPLE_GAME.address, {
        value: ethers.utils.parseEther("1.0")
      });
      const contractBalanceAfter = await AUTO_LOOP.balance(SAMPLE_GAME.address);
      expect(contractBalanceAfter).to.equal(ethers.utils.parseEther("1.0"));
    });
    it("Controller can progress loop", async function () {
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      expect(shouldProgress.loopIsReady).to.equal(true);
      await AUTO_LOOP_VIA_CONTROLLER.progressLoop(
        SAMPLE_GAME.address,
        shouldProgress.progressWithData
      );
    });
    it("Does not progress loop if not enough time has passed", async function () {});
    it("charges autoloop compatible contract correctly", async function () {
      const contractBalanceBefore = await AUTO_LOOP.balance(
        SAMPLE_GAME.address
      );
      const startGas = 1;
      const gasPrice = 1;

      // emulate a transaction to progressLoop() which would be normally called by a CONTROLLER
      await AUTO_LOOP_VIA_CONTROLLER.progressLoop(SAMPLE_GAME.address, []);

      const contractBalanceAfter = await AUTO_LOOP.balance(SAMPLE_GAME.address);
      const gasUsed = startGas + AUTO_LOOP.gasBuffer();
      const gasCost = gasUsed * gasPrice;
      const fee = (gasCost * AUTO_LOOP.baseFee()) / 100;
      const totalCost = gasCost + fee;

      expect(contractBalanceAfter).to.equal(contractBalanceBefore - totalCost);
    });

    it("controller is compensated for cost of tx", async function () {
      const controllerBalanceBefore = await ethers.provider.getBalance(
        CONTROLLER
      );
      const startGas = 1;
      const gasPrice = 1;

      // emulate a transaction to progressLoop() which would be normally called by a CONTROLLER
      await AUTO_LOOP.progressLoop(SAMPLE_GAME.address, []);

      const controllerBalanceAfter = await ethers.provider.getBalance(
        CONTROLLER
      );
      const gasUsed = startGas + AUTO_LOOP.gasBuffer();
      const gasCost = gasUsed * gasPrice;
      const fee = (gasCost * AUTO_LOOP.baseFee()) / 100;
      const controllerFee = (fee * AUTO_LOOP.CONTROLLER_FEE_PORTION) / 100;
      const totalCost = gasCost + controllerFee;

      expect(controllerBalanceAfter).to.equal(
        controllerBalanceBefore + totalCost
      );
    });

    it("controller receives refund for gas + fee", async function () {
      const controllerBalanceBefore = await ethers.provider.getBalance(
        CONTROLLER
      );
      const startGas = 1;
      const gasPrice = 1;

      // emulate a transaction to progressLoop() which would be normally called by a CONTROLLER
      await AUTO_LOOP.progressLoop(SAMPLE_GAME.address, []);

      const controllerBalanceAfter = await ethers.provider.getBalance(
        CONTROLLER
      );
      const gasUsed = startGas + AUTO_LOOP.gasBuffer();
      const gasCost = gasUsed * gasPrice;
      const fee = (gasCost * AUTO_LOOP.baseFee()) / 100;
      const controllerFee = (fee * AUTO_LOOP.CONTROLLER_FEE_PORTION) / 100;
      const totalRefund = gasCost + controllerFee;

      expect(controllerBalanceAfter).to.equal(
        controllerBalanceBefore + totalRefund
      );
    });

    it("protocol receives fee from each tx", async function () {
      const protocolBalanceBefore = await AUTO_LOOP._protocolBalance();
      const startGas = 1;
      const gasPrice = 1;

      // emulate a transaction to progressLoop() which would be normally called by a CONTROLLER
      await AUTO_LOOP.progressLoop(SAMPLE_GAME.address, []);

      const protocolBalanceAfter = await AUTO_LOOP._protocolBalance();
      const gasUsed = startGas + AUTO_LOOP.gasBuffer();
      const gasCost = gasUsed * gasPrice;
      const fee = (gasCost * AUTO_LOOP.baseFee()) / 100;
      const protocolFee = (fee * AUTO_LOOP.PROTOCOL_FEE_PORTION) / 100;

      expect(protocolBalanceAfter).to.equal(
        protocolBalanceBefore + protocolFee
      );
    });
  });
});
