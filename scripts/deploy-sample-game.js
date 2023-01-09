const hre = require("hardhat");
const fs = require("fs");
const deployments = require("../deployments.json");
require("dotenv").config();

class Deployment {
  constructor() {
    this.deployments = deployments;
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
  const deployment = new Deployment();
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
      deployment.deployments[hre.network.name].GAME_LOOP_REGISTRAR
    );
    await tx.wait();
    console.log("Game loop registered.");

    deployment.deployments[hre.network.name].SAMPLE_GAME = game.address;
    deployment.save();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
