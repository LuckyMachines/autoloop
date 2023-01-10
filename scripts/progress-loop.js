const hre = require("hardhat");
const config = require("../controller.config.json");
require("dotenv").config();

// Pass contract address as argument
// yarn progress-loop <CONTRACT ADDRESS>

async function main() {
  const contractAddress = process.argv[2] ? process.argv[2] : null;
  if (contractAddress) {
    const GameLoopCompatibleInterfaceArtifact = require("../artifacts/contracts/GameLoopCompatibleInterface.sol/GameLoopCompatibleInterface.json");
    const PROVIDER_URL = process.env.TEST_MODE
      ? process.env.RPC_URL_TESTNET
      : process.env.RPC_URL;
    const PRIVATE_KEY = process.env.TEST_MODE
      ? process.env.PRIVATE_KEY_TESTNET
      : process.env.PRIVATE_KEY;
    const provider = new hre.ethers.providers.JsonRpcProvider(PROVIDER_URL);
    const wallet = new hre.ethers.Wallet(PRIVATE_KEY, provider);
    const externalGameLoopContract = new hre.ethers.Contract(
      contractAddress,
      GameLoopCompatibleInterfaceArtifact.abi,
      wallet
    );
    const check = await externalGameLoopContract.shouldProgressLoop();
    let needsUpdate = check.loopIsReady;
    let progressWithData = check.progressWithData;
    console.log(`Contract ${contractAddress} needs update: ${needsUpdate}`);
    if (needsUpdate) {
      const GameLoopArtifact = require("../artifacts/contracts/GameLoop.sol/GameLoop.json");
      const gameLoop = new hre.ethers.Contract(
        config[process.env.TEST_MODE ? "test" : "main"].GAME_LOOP,
        GameLoopArtifact.abi,
        wallet
      );

      // Set gas from contract settings
      let maxGas = await gameLoop.maxGas(contractAddress);
      if (Number(maxGas) == 0) {
        maxGas = await gameLoop.MAX_GAS();
      }
      const gasBuffer = await gameLoop.GAS_BUFFER();
      const gasToSend = Number(maxGas) + Number(gasBuffer);
      console.log("Calling progress loop on:", gameLoop.address);
      let tx = await gameLoop.progressLoop(contractAddress, progressWithData, {
        gasLimit: gasToSend
      });
      let receipt = await tx.wait();
      let gasUsed = receipt.gasUsed;
      console.log(`Progressed loop on contract ${contractAddress}.`);
      console.log(`Gas sent: ${gasToSend} Gas used: ${gasUsed}`);
    }
  } else {
    console.log("Contract address argument not set");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
