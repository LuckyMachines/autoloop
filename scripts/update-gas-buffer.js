const hre = require("hardhat");
const deployments = require("../deployments.json");

async function main() {
  // register controller with registrar contract
  const AutoLoop = await hre.ethers.getContractFactory("AutoLoop");
  const autoLoop = AutoLoop.attach(deployments[hre.network.name].AUTO_LOOP);
  const tx = await autoLoop.setGasBuffer("102134");
  await tx.wait();
  console.log("Gas Buffer Updated");
  const gasBuffer = await autoLoop.gasBuffer();
  console.log("Gas Buffer:", gasBuffer.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
