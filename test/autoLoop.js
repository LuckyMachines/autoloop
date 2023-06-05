const { assert, expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");
const exp = require("constants");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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
      const updateInterval = 0;
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
      const updateInterval = 0;
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
      // check balance of AUTO_LOOP is correct
      const autoLoopBalance = await ethers.provider.getBalance(
        AUTO_LOOP.address
      );
      expect(autoLoopBalance).to.equal(contractBalanceAfter);
    });
    it("Controller can progress loop", async function () {
      let initialNumber = await SAMPLE_GAME.number();
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      expect(shouldProgress.loopIsReady).to.equal(true);
      await AUTO_LOOP_VIA_CONTROLLER.progressLoop(
        SAMPLE_GAME.address,
        shouldProgress.progressWithData
      );
      let finalNumber = await SAMPLE_GAME.number();
      expect(finalNumber).to.equal(initialNumber + 1);
    });
    it("charges autoloop compatible contract correctly", async function () {
      // do something to move hh onto next block
      let gasBuffer = await AUTO_LOOP.gasBuffer();
      tx = await AUTO_LOOP.setGasBuffer(gasBuffer);
      await tx.wait();

      const contractBalanceBefore = await AUTO_LOOP.balance(
        SAMPLE_GAME.address
      );
      // console.log("ALCC balance before:", contractBalanceBefore.toString());
      const _gasPrice = "20000000000"; //20 gwei
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      expect(shouldProgress.loopIsReady).to.equal(true);

      tx = await AUTO_LOOP_VIA_CONTROLLER.progressLoop(
        SAMPLE_GAME.address,
        shouldProgress.progressWithData,
        {
          gasPrice: _gasPrice
        }
      );
      receipt = await tx.wait();

      // get latest AutoLoopProgressed event from AUTO_LOOP
      /*
      event AutoLoopProgressed(
        address indexed autoLoopCompatibleContract,
        uint256 indexed timeStamp,
        address controller,
        uint256 gasUsed,
        uint256 gasPrice,
        uint256 gasCost,
        uint256 fee
    );
      */
      const events = await AUTO_LOOP.queryFilter(
        AUTO_LOOP.filters.AutoLoopProgressed()
      );
      expect(events.length).to.equal(2);
      const event = events[events.length - 1];
      const gasUsed = event.args.gasUsed;
      const gasPrice = event.args.gasPrice;
      const gasCost = event.args.gasCost;
      const fee = event.args.fee;
      // console.log("Gas used:", gasUsed.toString());
      // console.log("Gas price:", gasPrice.toString());
      // console.log("Gas cost (total):", gasCost.toString());
      // console.log("Fee:", fee.toString());
      const contractGasUsed = gasUsed - gasBuffer;
      // console.log("Contract gas used:", contractGasUsed.toString());
      const contractTxCost = contractGasUsed * gasPrice;
      // console.log("Contract tx cost:", contractTxCost.toString());
      const feeCharged = ((fee / contractTxCost) * 100).toString() + "%";
      expect(feeCharged).to.equal("70%");
      // console.log("Fee charged:", feeCharged);

      const contractBalanceAfter = await AUTO_LOOP.balance(SAMPLE_GAME.address);
      expect(Number(contractBalanceAfter)).to.equal(
        Number(contractBalanceBefore) - Number(gasCost)
      );
      // console.log("ALCC balance after:", contractBalanceAfter.toString());
    });

    it("controller receives exact refund for gas + fee", async function () {
      // do something to move hh onto next block
      let gasBuffer = await AUTO_LOOP.gasBuffer();
      tx = await AUTO_LOOP.setGasBuffer(gasBuffer);
      await tx.wait();

      const controllerBalanceBefore = await ethers.provider.getBalance(
        CONTROLLER
      );
      console.log("Controller balance before:", controllerBalanceBefore);
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      expect(shouldProgress.loopIsReady).to.equal(true);

      const _gasPrice = "20000000000"; //20 gwei

      tx = await AUTO_LOOP_VIA_CONTROLLER.progressLoop(
        SAMPLE_GAME.address,
        shouldProgress.progressWithData,
        {
          gasPrice: _gasPrice
        }
      );
      receipt = await tx.wait();
      const actualGasUsed = receipt.gasUsed;

      // get latest AutoLoopProgressed event from AUTO_LOOP
      const events = await AUTO_LOOP.queryFilter(
        AUTO_LOOP.filters.AutoLoopProgressed()
      );
      expect(events.length).to.equal(3);
      const event = events[events.length - 1];
      const gasUsed = event.args.gasUsed;
      const fee = event.args.fee;

      const controllerBalanceAfter = await ethers.provider.getBalance(
        CONTROLLER
      );

      // check on-chain gas used is correct
      // console.log("Gas reported:", gasUsed.toString());
      // console.log("Actual gas used:", actualGasUsed);
      // console.log("Difference:", actualGasUsed - gasUsed);
      expect(gasUsed).to.equal(actualGasUsed);

      // check that gas has been refunded
      // console.log("Controller balance after:", controllerBalanceAfter);
      expect(controllerBalanceAfter).to.be.greaterThanOrEqual(
        controllerBalanceBefore
      );

      // check that correct fee has been received
      const txProfit = controllerBalanceAfter - controllerBalanceBefore;
      const feeReceived = Math.floor((txProfit / fee) * 100).toString() + "%";
      // console.log("Fee received:", feeReceived);
      expect(feeReceived).to.equal("40%");
    });

    it("protocol receives fee from each tx", async function () {
      // do something to move hh onto next block
      let gasBuffer = await AUTO_LOOP.gasBuffer();
      tx = await AUTO_LOOP.setGasBuffer(gasBuffer);
      await tx.wait();

      const protocolBalanceBefore = await AUTO_LOOP.protocolBalance();
      const shouldProgress = await SAMPLE_GAME.shouldProgressLoop();
      expect(shouldProgress.loopIsReady).to.equal(true);

      const _gasPrice = "20000000000"; //20 gwei

      tx = await AUTO_LOOP_VIA_CONTROLLER.progressLoop(
        SAMPLE_GAME.address,
        shouldProgress.progressWithData,
        {
          gasPrice: _gasPrice
        }
      );
      receipt = await tx.wait();

      const protocolBalanceAfter = await AUTO_LOOP.protocolBalance();

      const protocolProfit = protocolBalanceAfter - protocolBalanceBefore;

      const events = await AUTO_LOOP.queryFilter(
        AUTO_LOOP.filters.AutoLoopProgressed()
      );
      expect(events.length).to.equal(4);
      const event = events[events.length - 1];
      const fee = event.args.fee;

      const feeReceived =
        Math.floor((protocolProfit / fee) * 100).toString() + "%";
      // console.log("Fee received:", feeReceived);
      expect(feeReceived).to.equal("60%");
    });
  });
});
