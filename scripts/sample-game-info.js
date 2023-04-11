const hre = require("hardhat");
const fs = require("fs");
const deployments = require("../deployments.json");
require("dotenv").config();

const sampleGames = [
  "0x9733BAF00DdfBCeBEB0Fa681971a7aab2183338b",
  "0x7dF310BB51900d8FDAD4133f8Db3D320dA56B2b0",
  "0xB80562054d8F0a9DfCb3C22139cA01347699a124",
  "0x05A4F0bFf145429A839596877b9975fE1331782A",
  "0xbAA31E9D0c0688E1C5F563D8be192832Ca6E1Bf5",
  "0x238986cE0FDdFe874b7870c6E18628766f50b7a2"
];

async function main() {
  /*
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
  */
  const Game = await hre.ethers.getContractFactory("NumberGoUp");
  for (let i = 0; i < sampleGames.length; i++) {
    const game = Game.attach(sampleGames[i]);
    const gameNumber = await game.number();
    const gameInterval = await game.interval();
    const gameLastTimeStamp = await game.lastTimeStamp();
    console.log(`Current Game State for Game ${i + 1}:`);
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
