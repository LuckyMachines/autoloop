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
  const tx = await registrar.registerController();
  await tx.wait();
  console.log("Controller registered.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
