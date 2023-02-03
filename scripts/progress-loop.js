const hre = require("hardhat");
const config = require("../controller.config.json");
require("dotenv").config();

// Pass contract address as argument
// yarn progress-loop <CONTRACT ADDRESS>

async function main() {
  const contractAddress = process.argv[2] ? process.argv[2] : null;
  if (contractAddress) {
    const AutoLoopCompatibleInterfaceArtifact = require("../artifacts/contracts/AutoLoopCompatibleInterface.sol/AutoLoopCompatibleInterface.json");
    const PROVIDER_URL = config.testMode
      ? process.env.RPC_URL_TESTNET
      : process.env.RPC_URL;
    const PRIVATE_KEY = config.testMode
      ? process.env.PRIVATE_KEY_TESTNET
      : process.env.PRIVATE_KEY;
    const provider = new hre.ethers.providers.JsonRpcProvider(PROVIDER_URL);
    const wallet = new hre.ethers.Wallet(PRIVATE_KEY, provider);
    const externalAutoLoopContract = new hre.ethers.Contract(
      contractAddress,
      AutoLoopCompatibleInterfaceArtifact.abi,
      wallet
    );
    const check = await externalAutoLoopContract.shouldProgressLoop();
    let needsUpdate = check.loopIsReady;
    let progressWithData = check.progressWithData;
    console.log(`Contract ${contractAddress} needs update: ${needsUpdate}`);
    if (needsUpdate) {
      const AutoLoopArtifact = require("../artifacts/contracts/AutoLoop.sol/AutoLoop.json");
      const autoLoop = new hre.ethers.Contract(
        config[config.testMode ? "test" : "main"].AUTO_LOOP,
        AutoLoopArtifact.abi,
        wallet
      );

      // Set gas from contract settings
      let maxGas = await autoLoop.maxGas(contractAddress);
      if (Number(maxGas) == 0) {
        maxGas = await autoLoop.MAX_GAS();
      }
      const gasBuffer = await autoLoop.GAS_BUFFER();
      const gasToSend = Number(maxGas) + Number(gasBuffer);
      console.log("Calling progress loop on:", autoLoop.address);
      let tx = await autoLoop.progressLoop(contractAddress, progressWithData, {
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
