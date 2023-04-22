# Lucky Machines AutoLoop Worker

An AutoLoop worker you can run to earn profits and

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
