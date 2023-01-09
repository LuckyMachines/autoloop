const hre = require("hardhat");
const fs = require("fs");
const deployments = require("../deployments.json");
require("dotenv").config();

async function main() {
  if (!deployments[hre.network.name].GAME_LOOP_REGISTRAR) {
    console.log(
      "\nRegistrar not deployed. Run the deployment script or set the address in deployments.json first.\n"
    );
  } else {
    const UPDATE_INTERVAL = 60; // setting contract to want updates every >= 60 seconds

    const Game = await hre.ethers.getContractFactory("NumberGoUp");
    console.log("Deploying sample game...");
    const game = await Game.deploy(UPDATE_INTERVAL);
    await game.deployed();
    console.log("Game deployed to", game.address);

    // Register game loop...
    let tx = await game.registerGameLoop(
      deployments[hre.network.name].GAME_LOOP_REGISTRAR
    );
    await tx.wait();
    console.log("Game loop registered.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
