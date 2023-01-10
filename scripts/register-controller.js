const hre = require("hardhat");
const config = require("../controller.config.json");

async function main() {
  // register controller with registrar contract
  const GameLoopRegistrar = await hre.ethers.getContractFactory(
    "GameLoopRegistrar"
  );
  const registrar = GameLoopRegistrar.attach(
    config[hre.network.name].GAME_LOOP_REGISTRAR
  );
  try {
    const tx = await registrar.registerController();
    await tx.wait();
  } catch (err) {
    console.log(err.message);
  }

  // TODO: confirm controller is registered with registry
  const GameLoopRegistry = await hre.ethers.getContractFactory(
    "GameLoopRegistry"
  );
  const registry = GameLoopRegistry.attach(
    config[hre.network.name].GAME_LOOP_REGISTRY
  );

  let accounts = await ethers.provider.listAccounts();
  const isRegistered = await registry.isRegisteredController(accounts[0]);
  if (isRegistered) {
    console.log("Controller registered.");
  } else {
    console.log("Controller not registered");
  }

  const GameLoop = await hre.ethers.getContractFactory("GameLoop");
  const gameLoop = GameLoop.attach(config[hre.network.name].GAME_LOOP);
  const controllerRole = await gameLoop.CONTROLLER_ROLE();
  const hasControllerRole = await gameLoop.hasRole(controllerRole, accounts[0]);
  if (hasControllerRole) {
    console.log("Controller role set on game loop");
  } else {
    console.log("Controller role not set on game loop");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
