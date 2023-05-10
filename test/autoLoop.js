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
  describe("Worker + Updates", function () {
    // charges user correctly
    it("Registers worker", async function () {});
    // worker is compensated for cost of tx
    it("Registers worker", async function () {});
    // worker receives refund for gas + fee
    it("Registers worker", async function () {});
    // protocol wallet receives fee from each tx
    it("Registers worker", async function () {});
  });
});
