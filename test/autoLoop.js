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

  // Contract Factories
  let AUTO_LOOP;
  let AUTO_LOOP_REGISTRY;
  let AUTO_LOOP_REGISTRAR;
  let SAMPLE_GAME;

  // Access Roles
  let CONTROLLER_ROLE;
  let REGISTRY_ROLE;
  let REGISTRAR_ROLE;

  before(async function () {
    let tx;
    let receipt;

    ACCOUNTS = await ethers.provider.listAccounts();
    ADMIN = ACCOUNTS[0];
    CONTROLLER = ACCOUNTS[1];
    CONTROLLER_SIGNER = ethers.provider.getSigner(ACCOUNTS[1]);

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

  describe("Registration", function () {
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
    it("Registers GLCI", async function () {
      const updateInterval = 1;
      const Game = await hre.ethers.getContractFactory("NumberGoUp");
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
        "100000"
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
    it("Returns list of all registered contracts", async function () {
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
  describe("Controller", function () {});
});
