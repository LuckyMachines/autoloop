# Lucky Machines Game Loop

An on-chain game loop for your blockchain game.

## Create a game loop

- Deploy contracts
- Set registrar on registry (can be wallet or contract)
- Register game loop compatible contracts with registry (via registrar)

## Run the game loop server

- Set the game loop provider & wallet credentials
- Register wallet for server with game loop (via registrar)
- Set contract ping interval
- Run the game loop server (or servers) with controller privileges

Server privileges are extremely limited. This is so many users may safely act as nodes in a distributed game-loop. The most a game loop controller can do is trigger a contract's update function, which will revert and cost the malicious controller some gas if the contract does not want that update.

## Limitations over Chainlink Automation

- No off chain compute, all computations must be done on chain
- Relies on own server or network of servers to run
- Gas must be covered by each individual server

## To do:

- Add time based updates (currently only based on contract logic)
- Setup a public game loop run by Lucky Machines
  - charge for registry / usage
  - we'll run the first few servers
  - incentivize server nodes with some slice of the pie
