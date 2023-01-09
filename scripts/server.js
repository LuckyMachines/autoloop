const hre = require("hardhat");
require("dotenv").config();

let server;
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

  async start() {
    console.log("Starting server...");
    // console.log("Provider:", this.provider);
    // console.log("Wallet:", this.wallet);
    this.running = true;
    while (this.running) {
      // Ping contract here
      console.log("Ping:", Date.now());
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

function main() {
  server = new Server(
    process.argv[2] ? process.argv[2] : null,
    process.argv[3] ? process.argv[3] : null
  );
  server.start();
}

main();
