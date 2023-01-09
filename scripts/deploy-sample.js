const hre = require("hardhat");
const fs = require("fs");
require("dotenv").config();

async function main() {
  const Game = await hre.ethers.getContractFactory("NumberGoUp");
  console.log("Deploying sample game...");
  const game = await Game.deploy();
  await game.deployed();
  console.log("Game deployed to", game.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
