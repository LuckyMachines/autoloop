const hre = require("hardhat");
const fs = require("fs");
require("dotenv").config();

class Deployment {
  constructor(deploymentJSON) {
    this.deployments = deploymentJSON ? deploymentJSON : { test: {}, main: {} };
    this.path = `${process.cwd()}/deployments.json`;
  }
  save() {
    fs.writeFileSync(
      this.path,
      JSON.stringify(this.deployments, null, 4),
      (err) => {
        if (err) {
          console.log("error: unable to save deployments file");
        } else {
          console.log("Saved deployments");
        }
      }
    );
  }
}

async function main() {
  const deployment = new Deployment();

  let gameLoop;
  let gameLoopRegistry;
  let gameLoopRegistrar;

  const GameLoop = await hre.ethers.getContractFactory("GameLoop");
  const GameLoopRegistry = await hre.ethers.getContractFactory(
    "GameLoopRegistry"
  );
  const GameLoopRegistrar = await hre.ethers.getContractFactory(
    "GameLoopRegistrar"
  );

  if (!deployment.deployments[hre.network.name].GAME_LOOP) {
    // deploy GameLoop
    console.log("Deploying Game Loop...");
    gameLoop = await GameLoop.deploy();
    await gameLoop.deployed();
    console.log("Game Loop deployed to", gameLoop.address);
    deployment.deployments[hre.network.name].GAME_LOOP = gameLoop.address;
    deployment.save();
  } else {
    gameLoop = GameLoop.attach(
      deployment.deployments[hre.network.name].GAME_LOOP
    );
    console.log(
      "Game loop deployed at",
      deployment.deployments[hre.network.name].GAME_LOOP
    );
  }

  if (!deployment.deployments[hre.network.name].GAME_LOOP_REGISTRY) {
    // deploy GameLoopRegistry
    gameLoopRegistry = await GameLoopRegistry.deploy(
      process.env.TEST_MODE
        ? process.env.REGISTRY_ADMIN_ADDRESS_TESTNET
        : process.env.REGISTRY_ADMIN_ADDRESS
    );
    await gameLoopRegistry.deployed();
    console.log("Registry deployed to", gameLoopRegistry.address);
    deployment.deployments[hre.network.name].GAME_LOOP_REGISTRY =
      gameLoopRegistry.address;
    deployment.save();
  } else {
    gameLoopRegistry = GameLoopRegistry.attach(
      deployment.deployments[hre.network.name].GAME_LOOP_REGISTRY
    );
    console.log(
      "Game loop registry deployed at",
      deployment.deployments[hre.network.name].GAME_LOOP_REGISTRY
    );
  }

  if (!deployment.deployments[hre.network.name].GAME_LOOP_REGISTRAR) {
    // deploy GameLoopRegistrar
    gameLoopRegistrar = await GameLoopRegistrar.deploy(
      gameLoop.address,
      gameLoopRegistry.address,
      process.env.TEST_MODE
        ? process.env.REGISTRAR_ADMIN_ADDRESS_TESTNET
        : process.env.REGISTRAR_ADMIN_ADDRESS
    );
    await gameLoopRegistrar.deployed();
    console.log("Registrar deployed to", gameLoopRegistrar.address);
    deployment.deployments[hre.network.name].GAME_LOOP_REGISTRAR =
      gameLoopRegistrar.address;
    deployment.save();
  } else {
    gameLoopRegistrar = GameLoopRegistrar.attach(
      deployment.deployments[hre.network.name].GAME_LOOP_REGISTRAR
    );
    console.log(
      "Game loop registrar deployed at",
      deployment.deployments[hre.network.name].GAME_LOOP_REGISTRAR
    );
  }
  // set registrar on game loop
  console.log("setting registrar on game loop");
  let tx = await gameLoop.setRegistrar(gameLoopRegistrar.address);
  await tx.wait();
  // set registrar on registry
  console.log("Setting registrar on registry");
  tx = await gameLoopRegistry.setRegistrar(gameLoopRegistrar.address);
  await tx.wait();
  console.log("Registrar set.");

  console.log("Deployments complete.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
