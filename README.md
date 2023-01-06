# Lucky Machines Game Loop

An on-chain game loop for your blockchain game.

## Create a game loop

- Deploy contracts
- Set registrar on registry (can be wallet or contract)
- Register game loop compatible contracts with registry (via registrar)

## Integrate with some project

- Make your contract inherit from [GameLoopCompatible.sol](https://github.com/LuckyMachines/game-loop/blob/main/contracts/GameLoopCompatible.sol) (see [example](https://github.com/LuckyMachines/game-loop/blob/main/contracts/sample/NumberGoUp.sol))

## Run the game loop server

- Set the game loop provider & wallet credentials
- Register wallet for server with game loop (via registrar)
- Set contract ping interval
- Run the game loop server (or servers) with controller privileges

Server privileges are extremely limited. This is so many users may safely act as nodes in a distributed game-loop. The most a game loop controller can do is trigger a contract's update function, which will revert and cost the malicious controller some gas if the contract does not want that update.

## Limitations over Chainlink Automation

- No off chain compute for hybrid smart contracts, all computations must be done on chain

## To do:

- Add time based updates (currently only based on contract logic)
