const hre = require("hardhat");
const deployments = require("../deployments.json");
const inquirer = require("inquirer");

async function main() {
  // register controller with registrar contract
  const AutoLoopRegistrar = await hre.ethers.getContractFactory(
    "AutoLoopRegistrar"
  );
  const registrar = AutoLoopRegistrar.attach(
    deployments[hre.network.name].AUTO_LOOP_REGISTRAR
  );

  const questions = [];
  const whichAddress = {
    type: "input",
    name: "autoLoopContract",
    message: "AutoLoop compatible contract:",
    default: "0x"
  };
  const depositAmount = {
    type: "input",
    name: "depositAmount",
    message: "Deposit amount (whole tokens):",
    default: "1"
  };
  questions.push(whichAddress, depositAmount);
  const answers = await inquirer.prompt(questions);
  const address = answers.autoLoopContract;
  const amount = answers.depositAmount;

  const tx = await registrar.deposit(address, {
    value: hre.ethers.utils.parseEther(amount)
  });
  await tx.wait();
  console.log("Deposit complete");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
