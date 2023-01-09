const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // deploy GameLoop
  const GameLoop = await hre.ethers.getContractFactory("GameLoop");
  console.log("Deploying Game Loop...");
  const gameLoop = await GameLoop.deploy();
  await gameLoop.deployed();
  console.log("Game Loop deployed to", gameLoop.address);

  // deploy GameLoopRegistry
  const GameLoopRegistry = await hre.ethers.getContractFactory(
    "GameLoopRegistry"
  );
  const gameLoopRegistry = await GameLoopRegistry.deploy(
    process.env.TEST_MODE
      ? process.env.REGISTRY_ADMIN_ADDRESS_TESTNET
      : process.env.REGISTRY_ADMIN_ADDRESS
  );
  await gameLoopRegistry.deployed();
  console.log("Registry deployed to", gameLoopRegistry.address);

  // deploy GameLoopRegistrar
  const GameLoopRegistrar = await hre.ethers.getContractFactory(
    "GameLoopRegistrar"
  );
  const gameLoopRegistrar = await GameLoopRegistrar.deploy(
    gameLoopRegistry.address,
    process.env.TEST_MODE
      ? process.env.REGISTRAR_ADMIN_ADDRESS_TESTNET
      : process.env.REGISTRAR_ADMIN_ADDRESS
  );
  await gameLoopRegistrar.deployed();
  console.log("Registrar deployed to", gameLoopRegistry.address);

  // set registrar on registry
  console.log("Setting registrar on registry");
  let tx = await gameLoopRegistry.setRegistrar(gameLoopRegistrar.address);
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
