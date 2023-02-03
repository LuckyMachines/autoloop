// Register a contract externally. Must have DEFAULT_ADMIN_ROLE on AutoLoop compatible contract.
const inquirer = require("inquirer");
const hre = require("hardhat");
const config = require("../controller.config.json");
require("dotenv").config();

async function main() {
  let signers = await hre.ethers.getSigners();
  let registrant = signers[0].address;
  console.log("Registrant:", registrant);
  let tx;
  const questions = [];
  const whichAddress = {
    type: "input",
    name: "autoLoopContract",
    message: "AutoLoop compatible contract:",
    default: "0x"
  };
  questions.push(whichAddress);
  const answers = await inquirer.prompt(questions);
  const autoLoopContract = answers.autoLoopContract;
  console.log(
    `Unegistering contract on ${hre.network.name}: ${autoLoopContract}`
  );
  const Registrar = await hre.ethers.getContractFactory("AutoLoopRegistrar");
  const registrar = Registrar.attach(
    config[hre.network.name].AUTO_LOOP_REGISTRAR
  );
  const Registry = await hre.ethers.getContractFactory("AutoLoopRegistry");
  const registry = Registry.attach(config[hre.network.name].AUTO_LOOP_REGISTRY);

  // check if contract is already unregistered
  let isRegistered = await registry.isRegisteredAutoLoop(autoLoopContract);
  if (!isRegistered) {
    console.log(
      `AutoLoop compatible contract ${autoLoopContract} is unregistered.`
    );
  } else {
    // check if we can register / unregister this contract
    let canRegister = await registrar.canRegisterAutoLoop(
      registrant,
      autoLoopContract
    );
    if (canRegister) {
      try {
        tx = await registrar.unregisterAutoLoopFor(autoLoopContract);
        await tx.wait();

        // check registry to see if it has been unregistered
        isRegistered = await registry.isRegisteredAutoLoop(autoLoopContract);
        if (!isRegistered) {
          console.log(
            `AutoLoop compatible contract ${autoLoopContract} is unregistered.`
          );
        } else {
          console.log(
            `Unable to unregister AutoLoop compatible contract. Try again.`
          );
        }
      } catch (err) {
        console.log(
          `Error registering contract: ${autoLoopContract}. \n${err.message}`
        );
      }
    } else {
      console.log(
        "Registrant cannot unregister contract. Make sure you have DEFAULT_ADMIN_ROLE on AutoLoop compatible contract."
      );
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
