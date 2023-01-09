const hre = require("hardhat");
const deployments = require("../deployments.json");
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

    const PROVIDER_URL = process.env.TEST_MODE
      ? process.env.RPC_URL_TESTNET
      : process.env.RPC_URL;
    const PRIVATE_KEY = process.env.TEST_MODE
      ? process.env.PRIVATE_KEY_TESTNET
      : process.env.PRIVATE_KEY;
    this.provider = new hre.ethers.providers.JsonRpcProvider(PROVIDER_URL);
    this.wallet = new hre.ethers.Wallet(PRIVATE_KEY, this.provider);
  }

  async checkNeedsUpdate(contractAddress) {
    const GameLoopCompatibleInterface = await hre.ethers.getContractFactory(
      "GameLoopCompatibleInterface"
    );
    const externalGameLoopContract =
      GameLoopCompatibleInterface.attach(contractAddress);
    const needsUpdate = false;

    try {
      const check = await externalGameLoopContract.shouldProgressLoop();
      needsUpdate = check.loopIsReady;
    } catch (err) {
      console.log(
        `Error checking game loop compatible contract: ${contractAddress}.`
      );
      console.log(err.message);
    }

    return needsUpdate;
  }

  async performUpdate(contractAddress) {
    const GameLoopCompatibleInterface = await hre.ethers.getContractFactory(
      "GameLoopCompatibleInterface"
    );
    const externalGameLoopContract =
      GameLoopCompatibleInterface.attach(contractAddress);

    // confirm update is still needed and grab update data
    const check = await externalGameLoopContract.shouldProgressLoop();
    let needsUpdate = check.loopIsReady;
    let progressWithData = check.progressWithData;

    if (needsUpdate) {
      const GameLoop = await hre.ethers.getContractFactory("GameLoop");
      const gameLoop = GameLoop.attach(
        deployments[process.env.TEST_MODE ? "test" : "main"].GAME_LOOP
      );
      // Set gas from contract settings
      const maxGas = await gameLoop.maxGas(contractAddress);
      const gasBuffer = await gameLoop.GAS_BUFFER();
      const gasToSend = Number(maxGas) + Number(gasBuffer);
      let tx = await gameLoop.progressLoop(contractAddress, progressWithData, {
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
              `Error performing update on game loop compatible contract: ${queue.contracts[i]}`
            );
            contractsToRemove.push(queue.contracts[i]);
          }
        } else {
          contractsToRemove.push(queue.contracts[i]);
        }
      }
      contractsToRemove.forEach((contract) => {
        queue.removeContract(contract);
      });
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
    if (index >= 0) {
      this.contracts.splice(index, 1);
    }
  }
  async download() {
    // get queue from contracts
    try {
      this.contracts = await this.contractFactory.getRegisteredGameLoops();
      console.log("Downloaded queue:", this.contracts);
    } catch (err) {
      console.error(err);
    }
  }
}

async function registryContractFactory() {
  const GameLoopRegistry = await hre.ethers.getContractFactory(
    "GameLoopRegistry"
  );
  const registry = GameLoopRegistry.attach(
    deployments[process.env.TEST_MODE ? "test" : "main"].GAME_LOOP_REGISTRY
  );
}

async function setup() {
  const registryFactory = await registryContractFactory();
  queue = new Queue(registryContractFactory);
  server = new Server(
    process.argv[2] ? process.argv[2] : null,
    process.argv[3] ? process.argv[3] : null
  );
}

function main() {
  server.start();
}

setup()
  .then(main())
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
