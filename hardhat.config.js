require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-web3");
require("hardhat-contract-sizer");
require("hardhat-abi-exporter");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    test: {
      url: process.env.RPC_URL_TESTNET,
      accounts: [process.env.PRIVATE_KEY_TESTNET]
    },
    main: {
      url: process.env.RPC_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  solidity: "0.8.17",
  abiExporter: {
    runOnCompile: true,
    format: "json",
    only: [
      "AutoLoop.sol",
      "AutoLoopCompatible.sol",
      "AutoLoopCompatibleInterface.sol",
      "AutoLoopRegistrar.sol",
      "AutoLoopRegistry.sol",
      "AutoLoopRoles.sol"
    ]
  }
};
