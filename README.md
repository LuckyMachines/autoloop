# Lucky Machines AutoLoop

An on-chain automation loop for your blockchain automation needs. Perfect for on-chain game loops.

## Set Credentials

- Create a `.env` file with RPC URL & wallet private key (see `.env-example`)

## Create a loop

- Deploy contracts and set registrar

```shell
yarn deploy-test
```

## Integrate with some project

- Make your contract inherit from [AutoLoopCompatible.sol](https://github.com/LuckyMachines/autoloop/blob/main/contracts/AutoLoopCompatible.sol) (see [example](https://github.com/LuckyMachines/autoloop/blob/main/contracts/sample/NumberGoUp.sol))
- Register AutoLoop compatible contracts with registry in contract (see [example](https://github.com/LuckyMachines/autoloop/blob/main/contracts/sample/NumberGoUp.sol))

## Register AutoLoop compatible contract:

```shell
yarn register-contract-test
```

## Run the AutoLoop server

- Set contract addresses in controller config (`controller.config.json`)
- Register wallet for server with AutoLoop (via registrar)

```shell
yarn register-controller-test
```

- Run the AutoLoop server (or servers) with controller privileges

```shell
yarn server [PING_INTERVAL] [EXPIRATION]
```

Server privileges are extremely limited. This is so many users may safely act as nodes in a distributed AutoLoop. The most an AutoLoop controller can do is trigger a contract's update function, which will revert and cost the malicious controller some gas if the contract does not want that update.

## Limitations over Chainlink Automation

- No off chain compute for hybrid smart contracts, all computations must be done on chain

## To do:

- Create p2p network for nodes to communicate
- Add time based updates / cron jobs (updates currently only based on contract logic)
