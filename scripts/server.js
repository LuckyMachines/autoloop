const hre = require("hardhat");
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
  }
  async start() {
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
  console.log(process.argv);
  server = new Server(2, 10); // 2 second ping, 10 second expiration for testing
  server.start();
}

main();
