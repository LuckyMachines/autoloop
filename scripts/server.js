const { ethers } = require("hardhat");
const hre = require("hardhat");
const config = require("../controller.config.json");
require("dotenv").config();

let server;
let queue;

const DEFAULT_PING_INTERVAL = 10; // seconds
const oneWeek = 7 * 24 * 60 * 60;
const DEFAULT_EXPIRATION = oneWeek; // in seconds

function pause(time) {
  return new Promise((resolve) =>
    setTimeout(() => {
      resolve();
    }, time * 1000)
  );
}

// pass interval / expiration in seconds
class Server {
  constructor(interval, expiration) {
    this.pingInterval = interval ? interval : DEFAULT_PING_INTERVAL;
    this.running = false;
    this.expirationDate = expiration
      ? Date.now() + expiration * 1000
      : Date.now() + DEFAULT_EXPIRATION * 1000;

    const PROVIDER_URL = config.testMode
      ? process.env.RPC_URL_TESTNET
      : process.env.RPC_URL;
    const PRIVATE_KEY = config.testMode
      ? process.env.PRIVATE_KEY_TESTNET
      : process.env.PRIVATE_KEY;
    this.provider = new hre.ethers.providers.JsonRpcProvider(PROVIDER_URL);
    this.wallet = new hre.ethers.Wallet(PRIVATE_KEY, this.provider);
  }

  async checkNeedsUpdate(contractAddress) {
    const AutoLoopCompatibleInterfaceArtifact = require("../artifacts/contracts/AutoLoopCompatibleInterface.sol/AutoLoopCompatibleInterface.json");
    const externalAutoLoopContract = new ethers.Contract(
      contractAddress,
      AutoLoopCompatibleInterfaceArtifact.abi,
      server.wallet
    );
    let needsUpdate = false;

    try {
      const check = await externalAutoLoopContract.shouldProgressLoop();
      needsUpdate = check.loopIsReady;
    } catch (err) {
      console.log(
        `Error checking auto loop compatible contract: ${contractAddress}.`
      );
      console.log(err.message);
    }

    return needsUpdate;
  }

  async performUpdate(contractAddress) {
    const AutoLoopCompatibleInterfaceArtifact = require("../artifacts/contracts/AutoLoopCompatibleInterface.sol/AutoLoopCompatibleInterface.json");
    const externalAutoLoopContract = new ethers.Contract(
      contractAddress,
      AutoLoopCompatibleInterfaceArtifact.abi,
      server.wallet
    );

    // confirm update is still needed and grab update data
    const check = await externalAutoLoopContract.shouldProgressLoop();
    let needsUpdate = check.loopIsReady;
    let progressWithData = check.progressWithData;

    if (needsUpdate) {
      // const AutoLoop = await hre.ethers.getContractFactory("AutoLoop");
      const AutoLoopArtifact = require("../artifacts/contracts/AutoLoop.sol/AutoLoop.json");
      const autoLoop = new hre.ethers.Contract(
        config[config.testMode ? "test" : "main"].AUTO_LOOP,
        AutoLoopArtifact.abi,
        server.wallet
      );

      // Set gas from contract settings
      let maxGas = await autoLoop.maxGas(contractAddress);
      if (Number(maxGas) == 0) {
        maxGas = await autoLoop.MAX_GAS();
      }
      const gasBuffer = await autoLoop.GAS_BUFFER();
      const gasToSend = Number(maxGas) + Number(gasBuffer);
      let tx = await autoLoop.progressLoop(contractAddress, progressWithData, {
        gasLimit: gasToSend
      });
      let receipt = await tx.wait();
      let gasUsed = receipt.gasUsed;
      console.log(`Progressed loop on contract ${contractAddress}.`);
      console.log(`Gas used: ${gasUsed}`);
    } else {
      throw new Error(`Contract no longer needs update: ${contractAddress}`);
    }
  }

  async start() {
    console.log("Starting server...");
    // console.log("Provider:", this.provider);
    // console.log("Wallet:", this.wallet);
    this.running = true;
    while (this.running) {
      if (queue.contracts.length == 0) {
        // console.log("Downloading queue...");
        await queue.download();
      }
      let contractsToRemove = [];
      for (let i = 0; i < queue.contracts.length; i++) {
        const needsUpdate = await this.checkNeedsUpdate(queue.contracts[i]);
        if (needsUpdate) {
          try {
            await this.performUpdate(queue.contracts[i]);
            contractsToRemove.push(queue.contracts[i]);
            break; // only one update per interval
          } catch (err) {
            console.log(
              `Error performing update on auto loop compatible contract: ${queue.contracts[i]}`
            );
            console.log(err.message);
            contractsToRemove.push(queue.contracts[i]);
          }
        } else {
          contractsToRemove.push(queue.contracts[i]);
        }
      }
      if (contractsToRemove.length > 0) {
        // console.log("Clearing unused contracts...");
        contractsToRemove.forEach((contract) => {
          queue.removeContract(contract);
        });
      }
      // console.log("Ping:", Date.now());
      if (Date.now() > this.expirationDate) {
        await this.stop();
      } else {
        await pause(this.pingInterval);
      }
    }
    process.exit();
  }
  async stop() {
    console.log("Stopping server...");
    // do any final tasks before server is down
    this.running = false;
  }
}

class Queue {
  constructor(registryContractFactory) {
    this.contracts = [];
    this.contractFactory = registryContractFactory;
  }
  addContract(contractAddress) {
    this.contracts.push(contractAddress);
  }
  removeContract(contractAddress) {
    const index = this.contracts.indexOf(contractAddress);
    // console.log("contracts:", this.contracts);
    if (index >= 0) {
      const updatedContracts = [...this.contracts].splice(index, 1);
      this.contracts = updatedContracts;
    }
  }
  async download() {
    // get queue from contracts

    try {
      console.log("registry:", this.contractFactory.address);
      this.contracts = await this.contractFactory.getRegisteredAutoLoops();
      console.log("Queue:", this.contracts);
    } catch (err) {
      console.error(err);
    }
  }
}

async function registryContractFactory() {
  const AutoLoopRegistryArtifact = require("../artifacts/contracts/AutoLoopRegistry.sol/AutoLoopRegistry.json");

  const registry = new hre.ethers.Contract(
    config[config.testMode ? "test" : "main"].AUTO_LOOP_REGISTRY,
    AutoLoopRegistryArtifact.abi,
    server.wallet
  );
  return registry;
}

async function setup() {
  server = new Server(
    process.argv[2] ? process.argv[2] : null,
    process.argv[3] ? process.argv[3] : null
  );
  const registryFactory = await registryContractFactory();
  queue = new Queue(registryFactory);
  //console.log("Server:", server);
}

function main() {
  server.start();
}

setup()
  .then(() => {
    main();
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
