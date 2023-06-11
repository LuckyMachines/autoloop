require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-web3");
require("hardhat-contract-sizer");
require("hardhat-abi-exporter");
require("solidity-docgen");
require("hardhat-contract-sizer");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    godwoken_test: {
      url: process.env.RPC_URL_GW_TESTNET,
      accounts: [process.env.PRIVATE_KEY_GW_TESTNET],
      chainId: Number(process.env.CHAIN_ID_GW_TESTNET)
    },
    godwoken: {
      url: process.env.RPC_URL_GW,
      accounts: [process.env.PRIVATE_KEY_GW],
      chainId: Number(process.env.CHAIN_ID_GW)
    },
    sepolia: {
      url: process.env.RPC_URL_SEPOLIA,
      accounts: [process.env.PRIVATE_KEY_SEPOLIA],
      chainId: Number(process.env.CHAIN_ID_SEPOLIA)
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000
          }
        }
      },
      {
        version: "0.7.3",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000
          }
        }
      }
    ]
  },
  abiExporter: {
    runOnCompile: true,
    format: "json",
    only: [
      "AutoLoop.sol",
      "AutoLoopCompatible.sol",
      "AutoLoopCompatibleInterface.sol",
      "AutoLoopRegistrar.sol",
      "AutoLoopRegistry.sol",
      "AutoLoopRoles.sol",
      "NumberGoUp.sol"
    ]
  }
};
