# Lucky Machines AutoLoop

An on-chain automation loop for your blockchain automation needs. Perfect for on-chain game loops.

# Integrate with your smart contract

- Make your contract inherit from [AutoLoopCompatible.sol](https://github.com/LuckyMachines/autoloop/blob/main/contracts/AutoLoopCompatible.sol) (see [example](https://github.com/LuckyMachines/autoloop/blob/main/contracts/sample/NumberGoUp.sol))
- Register AutoLoop compatible contracts with registry in contract (see [example](https://github.com/LuckyMachines/autoloop/blob/main/contracts/sample/NumberGoUp.sol))

## Register AutoLoop compatible contract:

```shell
yarn register-contract-test
```

# Run a local worker
## Set Credentials

- Create a `.env` file with RPC URL & wallet private key (see `.env-example`)

## Run the AutoLoop worker

- Set contract addresses in controller config (`controller.config.json`)
- Register wallet as AutoLoop worker (via registrar)

```shell
yarn register-controller-test
```

- Run the AutoLoop worker with controller privileges

```shell
yarn start
```
