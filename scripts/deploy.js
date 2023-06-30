const { ethers, upgrades, network } = require("hardhat");
const fs = require("fs");
require("dotenv").config();
const deployments = require("../deployments.json");

class Deployment {
  constructor(deploymentJSON) {
    this.deployments = deploymentJSON
      ? deploymentJSON
      : { godwoken_test: {}, godwoken: {}, sepolia: {} };
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
  const deployment = new Deployment(deployments);

  let autoLoop;
  let autoLoopRegistry;
  let autoLoopRegistrar;

  const AutoLoop = await ethers.getContractFactory("AutoLoop");
  const AutoLoopRegistry = await ethers.getContractFactory("AutoLoopRegistry");
  const AutoLoopRegistrar = await ethers.getContractFactory(
    "AutoLoopRegistrar"
  );

  let registryAdminAddress;
  let registrarAdminAddress;

  switch (network.name) {
    case "godwoken_test":
      registryAdminAddress = process.env.REGISTRY_ADMIN_ADDRESS_GW_TESTNET;
      registrarAdminAddress = process.env.REGISTRAR_ADMIN_ADDRESS_GW_TESTNET;
      break;
    case "godwoken":
      registryAdminAddress = process.env.REGISTRY_ADMIN_ADDRESS_GW;
      registrarAdminAddress = process.env.REGISTRAR_ADMIN_ADDRESS_GW;
      break;
    case "sepolia":
    default:
      registryAdminAddress = process.env.REGISTRY_ADMIN_ADDRESS_SEPOLIA;
      registrarAdminAddress = process.env.REGISTRAR_ADMIN_ADDRESS_SEPOLIA;
      break;
  }

  if (!deployment.deployments[network.name].AUTO_LOOP) {
    // deploy AutoLoop
    console.log("Deploying Auto Loop...");
    // autoLoop = await AutoLoop.deploy();
    autoLoop = await upgrades.deployProxy(AutoLoop, ["0.1.0"], {
      initializer: "initialize(string)"
    });
    await autoLoop.deployed();
    console.log("Auto Loop deployed to", autoLoop.address);
    deployment.deployments[network.name].AUTO_LOOP = autoLoop.address;
    deployment.save();
  } else {
    autoLoop = AutoLoop.attach(deployment.deployments[network.name].AUTO_LOOP);
    console.log(
      "Auto loop deployed at",
      deployment.deployments[network.name].AUTO_LOOP
    );
  }

  if (!deployment.deployments[network.name].AUTO_LOOP_REGISTRY) {
    // deploy AutoLoopRegistry
    // autoLoopRegistry = await AutoLoopRegistry.deploy(registryAdminAddress);
    autoLoopRegistry = await upgrades.deployProxy(
      AutoLoopRegistry,
      [registryAdminAddress],
      {
        initializer: "initialize()"
      }
    );
    await autoLoopRegistry.deployed();
    console.log("Registry deployed to", autoLoopRegistry.address);
    deployment.deployments[network.name].AUTO_LOOP_REGISTRY =
      autoLoopRegistry.address;
    deployment.save();
  } else {
    autoLoopRegistry = AutoLoopRegistry.attach(
      deployment.deployments[network.name].AUTO_LOOP_REGISTRY
    );
    console.log(
      "Auto loop registry deployed at",
      deployment.deployments[network.name].AUTO_LOOP_REGISTRY
    );
  }

  if (!deployment.deployments[network.name].AUTO_LOOP_REGISTRAR) {
    // deploy AutoLoopRegistrar
    // autoLoopRegistrar = await AutoLoopRegistrar.deploy(
    //   autoLoop.address,
    //   autoLoopRegistry.address,
    //   registrarAdminAddress
    // );
    autoLoopRegistrar = await upgrades.deployProxy(
      AutoLoopRegistrar,
      [autoLoop.address, autoLoopRegistry.address, registrarAdminAddress],
      {
        initializer: "initialize(address,address,address)"
      }
    );
    await autoLoopRegistrar.deployed();
    console.log("Registrar deployed to", autoLoopRegistrar.address);
    deployment.deployments[network.name].AUTO_LOOP_REGISTRAR =
      autoLoopRegistrar.address;
    deployment.save();
  } else {
    autoLoopRegistrar = AutoLoopRegistrar.attach(
      deployment.deployments[network.name].AUTO_LOOP_REGISTRAR
    );
    console.log(
      "Auto loop registrar deployed at",
      deployment.deployments[network.name].AUTO_LOOP_REGISTRAR
    );
  }
  // set registrar on auto loop
  console.log("setting registrar on auto loop");
  let tx = await autoLoop.setRegistrar(autoLoopRegistrar.address);
  await tx.wait();
  // set registrar on registry
  console.log("Setting registrar on registry");
  tx = await autoLoopRegistry.setRegistrar(autoLoopRegistrar.address);
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
