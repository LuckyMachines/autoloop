const hre = require("hardhat");
const config = require("../controller.config.json");

async function main() {
  // register controller with registrar contract
  const GameLoopRegistry = await hre.ethers.getContractFactory(
    "GameLoopRegistry"
  );
  const registry = GameLoopRegistry.attach(
    config[hre.network.name].GAME_LOOP_REGISTRY
  );
  const registeredLoops = await registry.getRegisteredGameLoops();
  console.log("Registered game loops:", registeredLoops);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
