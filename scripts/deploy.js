const { ethers, upgrades, network } = require("hardhat");
const { Signer } = require("ethers");
const fs = require("fs");
require("dotenv").config();
const deployments = require("../deployments.json");
const customNonce = false;
const autoLoopNonce = 1050;

function toHex(int) {
  return "0x" + int.toString(16);
}

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

// Adding NonceManager
class NonceManager extends Signer {
  constructor(signer, nonce) {
    super();
    ethers.utils.defineReadOnly(this, "signer", signer);
    ethers.utils.defineReadOnly(this, "provider", signer.provider);
    this.nonce = nonce;
  }

  async sendTransaction(transaction) {
    transaction.nonce = this.nonce;
    const tx = await this.signer.sendTransaction(transaction);
    this.nonce++;
    return tx;
  }

  async getAddress() {
    return this.signer.getAddress();
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
  let pk = process.env.PRIVATE_KEY;

  switch (network.name) {
    case "godwoken_test":
      registryAdminAddress = process.env.REGISTRY_ADMIN_ADDRESS_GW_TESTNET;
      registrarAdminAddress = process.env.REGISTRAR_ADMIN_ADDRESS_GW_TESTNET;
      pk = process.env.PRIVATE_KEY_GW_TESTNET;
      break;
    case "godwoken":
      registryAdminAddress = process.env.REGISTRY_ADMIN_ADDRESS_GW;
      registrarAdminAddress = process.env.REGISTRAR_ADMIN_ADDRESS_GW;
      pk = process.env.PRIVATE_KEY_GW;
      break;
    case "sepolia":
    default:
      registryAdminAddress = process.env.REGISTRY_ADMIN_ADDRESS_SEPOLIA;
      registrarAdminAddress = process.env.REGISTRAR_ADMIN_ADDRESS_SEPOLIA;
      pk = process.env.PRIVATE_KEY_SEPOLIA;
      break;
  }

  const wallet = new ethers.Wallet(pk, ethers.provider);
  const nonceManagedWallet = new NonceManager(wallet, autoLoopNonce);

  if (!deployment.deployments[network.name].AUTO_LOOP) {
    console.log("Deploying Auto Loop...");

    console.log("Setting nonce to", autoLoopNonce);
    console.log("nonce hex:", toHex(autoLoopNonce));

    console.log("Deploying proxy...");
    if (customNonce) {
      const AutoLoopWithSigner = AutoLoop.connect(nonceManagedWallet);
      autoLoop = await upgrades.deployProxy(AutoLoopWithSigner, ["0.1.0"], {
        initializer: "initialize(string)"
      });
    } else {
      autoLoop = await upgrades.deployProxy(AutoLoop, ["0.1.0"], {
        initializer: "initialize(string)"
      });
    }
    await autoLoop.deployed();
    console.log("AutoLoop deployed to:", autoLoop.address);

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
    console.log("Deploying Auto Loop Registry...");

    if (customNonce) {
      const AutoLoopRegistryWithSigner =
        AutoLoopRegistry.connect(nonceManagedWallet);

      autoLoopRegistry = await upgrades.deployProxy(
        AutoLoopRegistryWithSigner,
        [registryAdminAddress],
        {
          initializer: "initialize(address)"
        }
      );
    } else {
      autoLoopRegistry = await upgrades.deployProxy(
        AutoLoopRegistry,
        [registryAdminAddress],
        {
          initializer: "initialize(address)"
        }
      );
    }
    await autoLoopRegistry.deployed();
    // await autoLoopRegistry.waitForDeployment();
    console.log("AutoLoopRegistry deployed to:", autoLoopRegistry.address);

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
    console.log("Deploying Auto Loop Registrar...");

    if (customNonce) {
      const AutoLoopRegistrarWithSigner =
        AutoLoopRegistrar.connect(nonceManagedWallet);

      autoLoopRegistrar = await upgrades.deployProxy(
        AutoLoopRegistrarWithSigner,
        [autoLoop.address, autoLoopRegistry.address, registrarAdminAddress],
        {
          initializer: "initialize(address,address,address)"
        }
      );
    } else {
      autoLoopRegistrar = await upgrades.deployProxy(
        AutoLoopRegistrar,
        [autoLoop.address, autoLoopRegistry.address, registrarAdminAddress],
        {
          initializer: "initialize(address,address,address)"
        }
      );
    }
    await autoLoopRegistrar.deployed();
    // await autoLoopRegistrar.waitForDeployment();
    console.log("AutoLoopRegistrar deployed to:", autoLoopRegistrar.address);

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
