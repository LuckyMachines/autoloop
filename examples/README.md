# AutoLoop Example Contracts

Complete, deployable examples demonstrating AutoLoop integration patterns.

## Contracts

### AutoCounter
The simplest possible AutoLoop contract. Increments a counter at a fixed interval.
- **Difficulty**: Beginner
- **VRF**: No
- **Use case**: Periodic tasks, heartbeats, scheduled operations

### CoinFlipper
A provably fair coin flip using VRF (verifiable random function).
- **Difficulty**: Intermediate
- **VRF**: Yes (ECVRF)
- **Use case**: Games, lotteries, random selections

### PriceAlerter
Monitors a Chainlink price feed and alerts on threshold crossings.
- **Difficulty**: Intermediate
- **VRF**: No
- **Use case**: Price monitoring, automated trading signals, notifications

## Deployment

### Local (Anvil)

```bash
# Start from the autoloop/ directory
cd autoloop

# Deploy AutoCounter (30s interval)
forge create examples/AutoCounter.sol:AutoCounter \
  --constructor-args 30 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Deploy CoinFlipper (60s interval)
forge create examples/CoinFlipper.sol:CoinFlipper \
  --constructor-args 60 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Sepolia

```bash
forge create examples/AutoCounter.sol:AutoCounter \
  --constructor-args 30 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --verify
```

## After Deployment

1. **Register** with AutoLoop:
   ```bash
   cast send $CONTRACT_ADDRESS "register(address)" $REGISTRAR_ADDRESS \
     --rpc-url $RPC_URL --private-key $PRIVATE_KEY
   ```

2. **Set max gas**:
   ```bash
   cast send $REGISTRAR_ADDRESS "setMaxGasFor(address,uint256)" $CONTRACT_ADDRESS 500000 \
     --rpc-url $RPC_URL --private-key $PRIVATE_KEY
   ```

3. **Fund** with ETH:
   ```bash
   cast send $REGISTRAR_ADDRESS "deposit(address)" $CONTRACT_ADDRESS \
     --value 0.5ether --rpc-url $RPC_URL --private-key $PRIVATE_KEY
   ```

4. **Watch** -- the worker will start executing your contract's logic automatically!
