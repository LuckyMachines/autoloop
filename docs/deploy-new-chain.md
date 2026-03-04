# Deploying AutoLoop to a New Chain

## Prerequisites
- Foundry installed (`forge`, `cast`)
- RPC URL and funded deployer wallet for the target chain
- Chain added to `deployments.json`

## Steps

### 1. Deploy Contracts
```bash
# Set environment
export RPC_URL=<chain-rpc-url>
export PRIVATE_KEY=<deployer-key>
export CHAIN_ID=<chain-id>

# Deploy core contracts
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify

# Or deploy individually:
forge create src/AutoLoopRegistry.sol:AutoLoopRegistry --rpc-url $RPC_URL --private-key $PRIVATE_KEY
forge create src/AutoLoop.sol:AutoLoop --rpc-url $RPC_URL --private-key $PRIVATE_KEY --constructor-args <registry-address>
forge create src/AutoLoopRegistrar.sol:AutoLoopRegistrar --rpc-url $RPC_URL --private-key $PRIVATE_KEY --constructor-args <autoloop-address>
```

### 2. Update Deployments
Add the deployed addresses to `deployments.json` under the chain ID key:
```json
{
  "<chain-id>": {
    "name": "<Chain Name>",
    "rpcUrl": "<rpc-url>",
    "etherscanUrl": "<explorer-url>",
    "contracts": {
      "AUTO_LOOP": "<deployed-address>",
      "AUTO_LOOP_REGISTRY": "<deployed-address>",
      "AUTO_LOOP_REGISTRAR": "<deployed-address>"
    }
  }
}
```

### 3. Update SDK
Add the new chain to `autoloop-sdk/src/addresses.ts`.

### 4. Update Dashboard
Add the chain to `autoloop-dashboard-v2/src/lib/contracts.ts` and wagmi provider config.

### 5. Deploy Workers
Create new Railway services for the chain:
```bash
# Set per-chain env vars
NETWORK=<chain-name>
RPC_URL_<CHAIN>=<rpc-url>
PRIVATE_KEY_<CHAIN>=<worker-key>
```

### 6. Verify
- Check contracts on block explorer
- Register a test contract
- Fund it
- Register a controller
- Verify worker picks it up and progresses

## Target Chains

| Chain | ID | Status |
|-------|-----|--------|
| Sepolia | 11155111 | Deployed |
| Base | 8453 | Planned |
| Arbitrum | 42161 | Planned |
| Polygon | 137 | Planned |
