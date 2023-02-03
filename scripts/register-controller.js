const hre = require("hardhat");
const config = require("../controller.config.json");

async function main() {
  // register controller with registrar contract
  const AutoLoopRegistrar = await hre.ethers.getContractFactory(
    "AutoLoopRegistrar"
  );
  const registrar = AutoLoopRegistrar.attach(
    config[hre.network.name].AUTO_LOOP_REGISTRAR
  );
  try {
    const tx = await registrar.registerController();
    await tx.wait();
  } catch (err) {
    console.log(err.message);
  }

  // TODO: confirm controller is registered with registry
  const AutoLoopRegistry = await hre.ethers.getContractFactory(
    "AutoLoopRegistry"
  );
  const registry = AutoLoopRegistry.attach(
    config[hre.network.name].AUTO_LOOP_REGISTRY
  );

  let accounts = await ethers.provider.listAccounts();
  const isRegistered = await registry.isRegisteredController(accounts[0]);
  if (isRegistered) {
    console.log("Controller registered.");
  } else {
    console.log("Controller not registered");
  }

  const AutoLoop = await hre.ethers.getContractFactory("AutoLoop");
  const autoLoop = AutoLoop.attach(config[hre.network.name].AUTO_LOOP);
  const controllerRole = await autoLoop.CONTROLLER_ROLE();
  const hasControllerRole = await autoLoop.hasRole(controllerRole, accounts[0]);
  if (hasControllerRole) {
    console.log("Controller role set on AutoLoop");
  } else {
    console.log("Controller role not set on AutoLoop");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
