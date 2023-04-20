# Lucky Machines AutoLoop

An on-chain automation loop for your blockchain automation needs. Perfect for on-chain game loops.

# Run a local worker
## Set Credentials

- Create a `.env` file with RPC URL & wallet private key (see `.env-example`)

## Integrate with some project

- Make your contract inherit from [AutoLoopCompatible.sol](https://github.com/LuckyMachines/autoloop/blob/main/contracts/AutoLoopCompatible.sol) (see [example](https://github.com/LuckyMachines/autoloop/blob/main/contracts/sample/NumberGoUp.sol))
- Register AutoLoop compatible contracts with registry in contract (see [example](https://github.com/LuckyMachines/autoloop/blob/main/contracts/sample/NumberGoUp.sol))

## Register AutoLoop compatible contract:

```shell
yarn register-contract-test
```

## Run the AutoLoop server

- Set contract addresses in controller config (`controller.config.json`)
- Register wallet as AutoLoop worker (via registrar)

```shell
yarn register-controller-test
```

- Run the AutoLoop server (or servers) with controller privileges

```shell
yarn start
```
