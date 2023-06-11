// Register a contract externally. Must have DEFAULT_ADMIN_ROLE on AutoLoop compatible contract.
const inquirer = require("inquirer");
const hre = require("hardhat");
const deployments = require("../deployments.json");
require("dotenv").config();

async function main() {
  let signers = await hre.ethers.getSigners();
  let registrant = signers[0].address;
  let tx;
  const Registry = await hre.ethers.getContractFactory("AutoLoopRegistry");
  const registry = Registry.attach(
    deployments[hre.network.name].AUTO_LOOP_REGISTRY
  );

  let registeredIndices = await registry.getRegisteredAutoLoopIndicesFor(
    registrant
  );
  console.log("Registered Indices: ", registeredIndices);

  let registeredContracts = await registry.getRegisteredAutoLoopsFor(
    registrant
  );

  // let registeredContracts = await registry.getRegisteredAutoLoopsFromList([
  //   registrant
  // ]);

  console.log("Registered Contracts: ", registeredContracts);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
