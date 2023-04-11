const { ethers } = require("hardhat");
const hre = require("hardhat");
const config = require("../controller.config.json");
require("dotenv").config();

let worker;
let queue;

const DEFAULT_PING_INTERVAL = 1; // # blocks to wait before checking
const DEFAULT_EXPIRATION = 0; // # updates to wait before shutting down, 0 = never

class Worker {
  constructor(interval, expiration) {
    this.pingInterval = interval ? interval : DEFAULT_PING_INTERVAL;
    this.expirationUpdates = expiration ? expiration : DEFAULT_EXPIRATION;
    this.totalUpdates = 0;
    this.totalBlocksPassed = 0;
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
      worker.wallet
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
      worker.wallet
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
        worker.wallet
      );

      // Set gas from contract settings
      let maxGas = await autoLoop.getMaxGasFor(contractAddress);
      const gasBuffer = await autoLoop.getGasBuffer();
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
    console.log("Starting worker...");
    // console.log("Provider:", this.provider);
    // console.log("Wallet:", this.wallet);
    worker.provider.on("block", async (blockNumber) => {
      if (this.totalBlocksPassed % this.pingInterval == 0) {
        let contractsToRemove = [];
        try {
          if (queue.contracts.length == 0) {
            console.log("Downloading queue...");
            await queue.download();
          }

          for (let i = 0; i < queue.contracts.length; i++) {
            const needsUpdate = await this.checkNeedsUpdate(queue.contracts[i]);
            if (needsUpdate) {
              try {
                await this.performUpdate(queue.contracts[i]);
                // contractsToRemove.push(queue.contracts[i]);
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
        } catch (err) {
          console.log(`Error at block ${blockNumber}\n${err.message}`);
        }
        if (contractsToRemove.length > 0) {
          // console.log("Clearing unused contracts...");
          contractsToRemove.forEach((contract) => {
            queue.removeContract(contract);
          });
        }
        this.totalUpdates++;
        if (
          this.expirationUpdates > 0 &&
          this.totalUpdates >= this.expirationUpdates
        ) {
          await this.stop();
        }
      }
      this.totalBlocksPassed++;
    });
  }

  async stop() {
    console.log("Stopping worker...");
    // do any final tasks before worker is down
    process.exit();
  }
}

class Queue {
  constructor(registryContractFactory) {
    this.contracts = [];
    this.contractFactory = registryContractFactory;
  }
  addContract(contractAddress) {
    const index = this.contracts.indexOf(contractAddress);
    if (index < 0) {
      this.contracts.push(contractAddress);
    }
  }
  removeContract(contractAddress) {
    const index = this.contracts.indexOf(contractAddress);
    // console.log("contracts:", this.contracts);
    if (index >= 0) {
      this.contracts.splice(index, 1);
    }
  }
  async download() {
    // get queue from contracts

    try {
      console.log("registry:", this.contractFactory.address);
      const allowList = config[config.testMode ? "test" : "main"].allowList;
      const blockList = config[config.testMode ? "test" : "main"].blockList;
      let contracts;
      if (allowList.length > 0) {
        console.log("Downloading with allow list", allowList);
        contracts = await this.contractFactory.getRegisteredAutoLoopsFromList(
          allowList
        );
        const isRegistered1 = await this.contractFactory.isRegisteredAutoLoop(
          "0x9733BAF00DdfBCeBEB0Fa681971a7aab2183338b"
        );
        const isRegistered2 = await this.contractFactory.isRegisteredAutoLoop(
          "0x7dF310BB51900d8FDAD4133f8Db3D320dA56B2b0"
        );
        const registeredLoops =
          await this.contractFactory.getRegisteredAutoLoopsFor(
            "0x3804f754C18520726f3FC7eEd8E160dC79d4B7f8"
          );
        console.log("1 registered:", isRegistered1);
        console.log("2 registered:", isRegistered2);
        console.log("registered loops:", registeredLoops);
      } else {
        if (blockList.length > 0) {
          console.log("Downloading all registered contracts");
          contracts = await this.contractFactory.getRegisteredAutoLoops();
        } else {
          console.log("Downloading excluding block list");
          contracts =
            await this.contractFactory.getRegisteredAutoLoopsExcludingList(
              blockList
            );
        }
      }
      console.log("Queue:", contracts);
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
    worker.wallet
  );
  return registry;
}

async function setup() {
  worker = new Worker(
    process.argv[2] ? process.argv[2] : null,
    process.argv[3] ? process.argv[3] : null
  );
  const registryFactory = await registryContractFactory();
  queue = new Queue(registryFactory);
  //console.log("Worker:", worker);
}

function main() {
  worker.start();
}

setup()
  .then(() => {
    main();
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
