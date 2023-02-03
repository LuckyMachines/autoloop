const hre = require("hardhat");
const config = require("../controller.config.json");

async function main() {
  // register controller with registrar contract
  const AutoLoopRegistry = await hre.ethers.getContractFactory(
    "AutoLoopRegistry"
  );
  const registry = AutoLoopRegistry.attach(
    config[hre.network.name].AUTO_LOOP_REGISTRY
  );
  const registeredLoops = await registry.getRegisteredAutoLoops();
  console.log("Registered AutoLoops:", registeredLoops);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
