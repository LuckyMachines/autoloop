const hre = require("hardhat");
const fs = require("fs");
const deployments = require("../deployments.json");
require("dotenv").config();

async function main() {
  if (!deployments[hre.network.name].AUTO_LOOP_REGISTRAR) {
    console.log(
      "\nRegistrar not deployed. Run the deployment script or set the address in deployments.json first.\n"
    );
  } else if (!deployments[hre.network.name].SAMPLE_GAME) {
    console.log("\n Sample game not deployed.\n");
  } else {
    const Game = await hre.ethers.getContractFactory("NumberGoUp");
    const game = Game.attach(deployments[hre.network.name].SAMPLE_GAME);
    const gameNumber = await game.number();
    const gameInterval = await game.interval();
    const gameLastTimeStamp = await game.lastTimeStamp();
    console.log(`Current Game State for ${game.address}:`);
    console.log(
      `#:${gameNumber.toString()}\ninterval:${gameInterval}\nlast time stamp:${gameLastTimeStamp}`
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
