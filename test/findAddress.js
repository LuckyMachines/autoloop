const { assert, expect } = require("chai");
const { ethers } = require("hardhat");
const fs = require("fs");
require("dotenv").config();

const startingNonce = 9000;
const stoppingNonce = 20000;

const targetWords = ["c0de", "5afe", "ab1e", "aced", "d1ce", "ba5e"];

describe("Auto Loop", function () {
  // Accounts
  let ACCOUNTS;
  let ADMIN;
  let ADMIN_SIGNER;
  let CONTROLLER;
  let CONTROLLER_SIGNER;
  let ADMIN_2;
  let ADMIN_2_SIGNER;
  let CONTROLLER_2;
  let CONTROLLER_2_SIGNER;

  // Contract Factories
  let AUTO_LOOP;
  let AUTO_LOOP_REGISTRY;
  let AUTO_LOOP_REGISTRAR;
  // Access Roles
  let CONTROLLER_ROLE;
  let REGISTRY_ROLE;
  let REGISTRAR_ROLE;

  let tx;
  let receipt;

  // convert int to hex
  function toHex(int) {
    return "0x" + int.toString(16);
  }

  before(async function () {
    ACCOUNTS = await ethers.provider.listAccounts();
    console.log("Accounts:", ACCOUNTS);
    ADMIN = ACCOUNTS[0];
    ADMIN_SIGNER = ethers.provider.getSigner(ACCOUNTS[0]);
    CONTROLLER = ACCOUNTS[1];
    CONTROLLER_SIGNER = ethers.provider.getSigner(ACCOUNTS[1]);
    ADMIN_2 = ACCOUNTS[2];
    ADMIN_2_SIGNER = ethers.provider.getSigner(ACCOUNTS[2]);
    CONTROLLER_2 = ACCOUNTS[3];
    CONTROLLER_2_SIGNER = ethers.provider.getSigner(ACCOUNTS[3]);

    /*
    const AutoLoopRegistry = await hre.ethers.getContractFactory(
      "AutoLoopRegistry"
    );
    const AutoLoopRegistrar = await hre.ethers.getContractFactory(
      "AutoLoopRegistrar"
    );

    // AutoLoopRegistry
    AUTO_LOOP_REGISTRY = await AutoLoopRegistry.deploy(ADMIN);
    await AUTO_LOOP_REGISTRY.deployed();
    console.log("Registry deployed to", AUTO_LOOP_REGISTRY.address);

    // AutoLoop
    

    // // AutoLoopRegistrar
    // AUTO_LOOP_REGISTRAR = await AutoLoopRegistrar.deploy(
    //   AUTO_LOOP.address,
    //   AUTO_LOOP_REGISTRY.address,
    //   ADMIN
    // );
    // await AUTO_LOOP_REGISTRAR.deployed();
    // console.log("Registrar deployed to", AUTO_LOOP_REGISTRAR.address);

    // console.log("Getting access roles");
    // CONTROLLER_ROLE = await AUTO_LOOP.CONTROLLER_ROLE();
    // REGISTRY_ROLE = await AUTO_LOOP.REGISTRY_ROLE();
    // REGISTRAR_ROLE = await AUTO_LOOP.REGISTRAR_ROLE();
    // console.log("Controller role:", CONTROLLER_ROLE);
    */
  });

  describe("Registration + Admin", function () {
    it("Deploys from address", async function () {
      const PRIVATE_KEY = process.env.PRIVATE_KEY;
      const provider = hre.ethers.provider;
      const wallet = new hre.ethers.Wallet(PRIVATE_KEY, provider);

      const adminBalance = await provider.getBalance(ADMIN);
      console.log(
        "Admin balance: ",
        hre.ethers.utils.formatEther(adminBalance)
      );

      // transfer some ETH to the wallet from Admin
      tx = await ADMIN_SIGNER.sendTransaction({
        to: wallet.address,
        value: hre.ethers.utils.parseEther("9999.0")
      });

      // get wallet balance
      const balance = await provider.getBalance(wallet.address);
      console.log("Wallet address:", wallet.address);
      console.log("Wallet balance: ", hre.ethers.utils.formatEther(balance));

      const AutoLoop = await hre.ethers.getContractFactory("AutoLoop");

      // set nonce
      await hre.network.provider.send("hardhat_setNonce", [
        wallet.address,
        toHex(startingNonce)
      ]);

      for (let i = startingNonce; i < stoppingNonce; i++) {
        AUTO_LOOP = await AutoLoop.connect(wallet).deploy();
        await AUTO_LOOP.deployed();
        if (i % 500 === 0) {
          console.log("Checking nonce:", i);
        }
        // console.log(
        //   "AutoLoop deployed w/nonce:",
        //   AUTO_LOOP.deployTransaction.nonce
        // );
        // console.log(
        //   `Address: ${AUTO_LOOP.address}, nonce: ${AUTO_LOOP.deployTransaction.nonce}`
        // );

        // Check if first 4 characters of address after 0x or the last 4 characters match
        // any of the target words in targetWords array.
        const address = AUTO_LOOP.address;
        const addressString = address.toString();
        const addressSubstring = addressString.substring(2, 6);
        const addressSubstringLower = addressSubstring.toLowerCase();
        const addressSubstringEnd = addressString.substring(
          addressString.length - 4,
          addressString.length
        );
        const addressSubstringEndLower = addressSubstringEnd.toLowerCase();
        if (
          targetWords.includes(addressSubstringLower) &&
          targetWords.includes(addressSubstringEndLower)
        ) {
          console.log(
            "word match start + end:",
            addressSubstringLower,
            addressSubstringEndLower
          );
          console.log("Address:", address);
          console.log("Nonce:", AUTO_LOOP.deployTransaction.nonce);
          console.log("Wallet address:", wallet.address);
        } else if (targetWords.includes(addressSubstringLower)) {
          console.log("word match start:", addressSubstringLower);
          console.log("Address:", address);
          console.log("Nonce:", AUTO_LOOP.deployTransaction.nonce);
          console.log("Wallet address:", wallet.address);
        } else if (targetWords.includes(addressSubstringEndLower)) {
          console.log("word match end:", addressSubstringEndLower);
          console.log("Address:", address);
          console.log("Nonce:", AUTO_LOOP.deployTransaction.nonce);
          console.log("Wallet address:", wallet.address);
        }
      }
    });
  });
});
