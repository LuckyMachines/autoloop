const { assert, expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");
const exp = require("constants");

describe("Game Loop", function () {
  // Accounts
  let ACCOUNTS;
  let ADMIN;
  let CONTROLLER;
  let CONTROLLER_SIGNER;

  // Contract Factories
  let GAME_LOOP;
  let GAME_LOOP_REGISTRY;
  let GAME_LOOP_REGISTRAR;
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

    const GameLoop = await hre.ethers.getContractFactory("GameLoop");
    const GameLoopRegistry = await hre.ethers.getContractFactory(
      "GameLoopRegistry"
    );
    const GameLoopRegistrar = await hre.ethers.getContractFactory(
      "GameLoopRegistrar"
    );

    // GameLoop
    console.log("Deploying Game Loop...");
    GAME_LOOP = await GameLoop.deploy();
    await GAME_LOOP.deployed();
    console.log("Game Loop deployed to", GAME_LOOP.address);

    // GameLoopRegistry
    GAME_LOOP_REGISTRY = await GameLoopRegistry.deploy(ADMIN);
    await GAME_LOOP_REGISTRY.deployed();
    console.log("Registry deployed to", GAME_LOOP_REGISTRY.address);

    // GameLoopRegistrar
    GAME_LOOP_REGISTRAR = await GameLoopRegistrar.deploy(
      GAME_LOOP.address,
      GAME_LOOP_REGISTRY.address,
      ADMIN
    );
    await GAME_LOOP_REGISTRAR.deployed();
    console.log("Registrar deployed to", GAME_LOOP_REGISTRAR.address);

    console.log("Getting access roles");
    CONTROLLER_ROLE = await GAME_LOOP.CONTROLLER_ROLE();
    REGISTRY_ROLE = await GAME_LOOP.REGISTRY_ROLE();
    REGISTRAR_ROLE = await GAME_LOOP.REGISTRAR_ROLE();
    console.log("Controller role:", CONTROLLER_ROLE);
  });

  describe("Registration", function () {
    it("Sets registrar", async function () {
      tx = await GAME_LOOP_REGISTRY.setRegistrar(GAME_LOOP_REGISTRAR.address);
      await tx.wait();
      let hasRegistrarRole = await GAME_LOOP_REGISTRY.hasRole(
        REGISTRAR_ROLE,
        GAME_LOOP_REGISTRAR.address
      );
      expect(hasRegistrarRole).to.equal(true);

      tx = await GAME_LOOP.setRegistrar(GAME_LOOP_REGISTRAR.address);
      await tx.wait();
      hasRegistrarRole = await GAME_LOOP.hasRole(
        REGISTRAR_ROLE,
        GAME_LOOP_REGISTRAR.address
      );
      expect(hasRegistrarRole).to.equal(true);
    });
    it("Registers GLCI", async function () {
      const updateInterval = 1;
      const Game = await hre.ethers.getContractFactory("NumberGoUp");
      SAMPLE_GAME = await Game.deploy(updateInterval);
      await SAMPLE_GAME.deployed();

      let isRegistered = await GAME_LOOP_REGISTRY.isRegisteredGameLoop(
        SAMPLE_GAME.address
      );
      expect(isRegistered).to.equal(false);

      const canRegister = await GAME_LOOP_REGISTRAR.canRegisterGameLoop(
        SAMPLE_GAME.address
      );
      expect(canRegister).to.equal(true);

      tx = await SAMPLE_GAME.registerGameLoop(GAME_LOOP_REGISTRAR.address);
      await tx.wait();
      isRegistered = await GAME_LOOP_REGISTRY.isRegisteredGameLoop(
        SAMPLE_GAME.address
      );
      expect(isRegistered).to.equal(true);
    });
    it("Registers Controller", async function () {
      const registrarArtifact = require("../artifacts/contracts/GameLoopRegistrar.sol/GameLoopRegistrar.json");
      const registrarViaController = new ethers.Contract(
        GAME_LOOP_REGISTRAR.address,
        registrarArtifact.abi,
        CONTROLLER_SIGNER
      );
      let isRegistered = await GAME_LOOP_REGISTRY.isRegisteredController(
        CONTROLLER
      );
      expect(isRegistered).to.equal(false);

      const canRegister = await GAME_LOOP_REGISTRAR.canRegisterController(
        CONTROLLER
      );
      expect(canRegister).to.equal(true);

      tx = await registrarViaController.registerController();
      await tx.wait();
      isRegistered = await GAME_LOOP_REGISTRY.isRegisteredController(
        CONTROLLER
      );
      expect(isRegistered).to.equal(true);
    });
  });
});
