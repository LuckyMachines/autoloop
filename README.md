# Lucky Machines AutoLoop

An on-chain automation loop for your blockchain automation needs. Perfect for on-chain game loops.

## AI Agent Quickstart

This repository is optimized for automated code agents and LLM retrieval:

- Machine-readable project summary: `llms.txt`
- API and contract reference: `docs/index.md`
- Gas and economics assumptions: `gas-cost-analysis.md`
- ABI artifacts for integration tooling: `abi/contracts/*`

Start here:

1. Read `llms.txt` and `README.md`
2. Compile and test with `npm run build` and `npm run test`
3. Extract latest ABI bundle with `npm run extract-abi`
4. Pair with `autoloop-worker` for loop execution and VRF proof delivery

## Installation

AutoLoop is published to the Lucky Machines package registry.

Add the registry to your project's `.npmrc`:

```
@luckymachines:registry=https://packages.luckymachines.io
```

Then install:

```bash
npm install @luckymachines/autoloop
```

For Foundry projects, add a remapping to `remappings.txt`:

```
@luckymachines/autoloop/=node_modules/@luckymachines/autoloop/
```

## Integrate with Your Smart Contract

### Standard Loop

Inherit from [`AutoLoopCompatible.sol`](https://github.com/LuckyMachines/autoloop/blob/main/src/AutoLoopCompatible.sol) and implement two functions:

```solidity
import "@luckymachines/autoloop/src/AutoLoopCompatible.sol";

contract MyGame is AutoLoopCompatible {
    function shouldProgressLoop()
        external view override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = /* your condition */;
        progressWithData = abi.encode(_loopID);
    }

    function progressLoop(bytes calldata progressWithData) external override {
        uint256 loopID = abi.decode(progressWithData, (uint256));
        require(loopID == _loopID, "stale");
        // your game logic here
        ++_loopID;
    }
}
```

See [`NumberGoUp.sol`](https://github.com/LuckyMachines/autoloop/blob/main/src/sample/NumberGoUp.sol) for a complete example.

### Loop with Verifiable Randomness

For contracts that need provably fair randomness, inherit from [`AutoLoopVRFCompatible.sol`](https://github.com/LuckyMachines/autoloop/blob/main/src/AutoLoopVRFCompatible.sol) instead:

**How VRF works:**

1. Your contract returns `shouldProgressLoop() => true` with the current `_loopID`
2. The worker detects VRF support via ERC-165 (`supportsInterface`)
3. The worker generates an ECVRF proof off-chain using its private key and a deterministic seed
4. The proof is wrapped around your game data and submitted to `progressLoop()`
5. [`VRFVerifier.sol`](https://github.com/LuckyMachines/autoloop/blob/main/src/VRFVerifier.sol) verifies the proof on-chain and outputs a `bytes32` random value

**Solidity integration (3 steps):**

```solidity
import "@luckymachines/autoloop/src/AutoLoopVRFCompatible.sol";

contract MyVRFGame is AutoLoopVRFCompatible {
    // 1. shouldProgressLoop — same as standard loop
    function shouldProgressLoop()
        external view override
        returns (bool loopIsReady, bytes memory progressWithData)
    {
        loopIsReady = /* your condition */;
        progressWithData = abi.encode(_loopID);
    }

    // 2. progressLoop — verify VRF and use the randomness
    function progressLoop(bytes calldata progressWithData) external override {
        (bytes32 randomness, bytes memory gameData) =
            _verifyAndExtractRandomness(progressWithData, tx.origin);

        uint256 loopID = abi.decode(gameData, (uint256));
        require(loopID == _loopID, "stale");

        // Use randomness: e.g. uint256(randomness) % 6 + 1
        ++_loopID;
    }
}
```

```solidity
// 3. Register the controller's VRF public key (call once per controller)
myVRFGame.registerControllerKey(controllerAddress, pkX, pkY);
```

See [`RandomGame.sol`](https://github.com/LuckyMachines/autoloop/blob/main/src/sample/RandomGame.sol) for a complete VRF example.

---

# Protocol Economics

AutoLoop charges a fee on every loop execution to sustain the protocol and compensate controllers (the off-chain bots that trigger `progressLoop()`).

## Fee-on-Execution Model

Every call to `progressLoop()` charges the registered contract owner:

1. **Gas reimbursement** — actual gas consumed (including a fixed buffer of 94,293 gas for overhead)
2. **Base fee** — 70% of the update's gas cost, charged on top of gas reimbursement

The base fee is computed only on the gas used by the contract's `progressLoop()` call itself (not the buffer overhead).

## Protocol / Controller Split

The base fee is split between the protocol (Lucky Machines) and the controller that executed the transaction:

| Recipient | Share of base fee |
|---|---|
| Protocol | 60% |
| Controller | 40% |

The controller also receives the full gas reimbursement.

## Fee Calculation

From `AutoLoop.sol` `progressLoop()` (lines 125-137):

```
fee            = (txGas * tx.gasprice * 70) / 100
controllerFee  = (fee * 40) / 100
totalCost      = gasCost + fee

Controller receives:  gasCost + controllerFee
Protocol accumulates: fee - controllerFee
Contract is charged:  totalCost
```

### Worked Example

Assume a loop execution uses **200,000 gas** at a gas price of **50 gwei**:

| Item | Calculation | Amount |
|---|---|---|
| Gas used (with buffer) | 200,000 + 94,293 | 294,293 gas |
| Gas cost (reimbursement) | 294,293 × 50 gwei | 0.01471465 ETH |
| Base fee | (200,000 × 50 gwei × 70) / 100 | 0.007 ETH |
| Controller fee (40% of base fee) | 0.007 × 40 / 100 | 0.0028 ETH |
| Protocol fee (60% of base fee) | 0.007 × 60 / 100 | 0.0042 ETH |
| **Total charged to contract** | 0.01471465 + 0.007 | **0.02171465 ETH** |
| **Controller receives** | 0.01471465 + 0.0028 | **0.01751465 ETH** |
| **Protocol accumulates** | 0.007 - 0.0028 | **0.0042 ETH** |

## Deposits & Balances

Contract owners must deposit ETH into AutoLoop before their contract can be executed. Each `progressLoop()` call deducts `totalCost` from the contract's balance. If the balance is too low to cover gas + fees, the transaction reverts.

Deposits are made through the registrar role via `deposit(registeredUser)`.

## Refunds

Contract owners can request a refund of their entire unused balance via `requestRefund()` (called through the registrar). The full remaining balance is sent to the specified address and the on-chain balance is reset to zero.

## Protocol Fee Withdrawal

Accumulated protocol fees are tracked in `_protocolBalance`. The admin can withdraw any amount up to the accumulated balance by calling:

```solidity
withdrawProtocolFees(uint256 amount, address toAddress)
```

## Configurable Parameters

All parameters below can be adjusted by the contract admin (`DEFAULT_ADMIN_ROLE`):

| Parameter | Default | Setter | Description |
|---|---|---|---|
| `BASE_FEE` | 70 | — | % of gas cost charged as fee (not directly settable post-init) |
| `PROTOCOL_FEE_PORTION` | 60 | `setProtocolFeePortion()` | % of base fee to protocol |
| `CONTROLLER_FEE_PORTION` | 40 | `setControllerFeePortion()` | % of base fee to controller |
| `MAX_GAS` | 1,000,000 | `setMaxGasDefault()` | Default max gas per execution |
| `MAX_GAS_PRICE` | 40,000,000,000,000 (40k gwei) | `setMaxGasPriceDefault()` | Default max gas price (wei) |
| `GAS_BUFFER` | 94,293 | `setGasBuffer()` | Overhead gas outside contract update |
| `GAS_THRESHOLD` | 14,905,707 | `setGasThreshold()` | Highest gas a user can set (15M - buffer) |

Setting `PROTOCOL_FEE_PORTION` automatically adjusts `CONTROLLER_FEE_PORTION` to `100 - value`, and vice versa. Both must be ≤ 100.

Per-contract overrides for `maxGas` and `maxGasPrice` can be set through the registrar via `setMaxGas()` and `setMaxGasPrice()`.

---

## Gas Costs

| Loop Type | Median Gas | Notes |
|-----------|-----------|-------|
| Standard (`NumberGoUp`) | ~90,000 | Time-based counter |
| VRF (`RandomGame`) | ~240,000 | Includes on-chain ECVRF proof verification |

VRF adds approximately 150k gas of overhead for the elliptic curve operations in `VRFVerifier.sol`. At current L1 gas prices (~0.05 gwei), the VRF overhead costs less than $0.001 per tick.

See [gas-cost-analysis.md](gas-cost-analysis.md) for full cost projections.

## Dashboard

The [autoloop-dashboard](https://github.com/LuckyMachines/autoloop-dashboard) provides a web UI for one-click local setup, contract deployment, worker management, and real-time event monitoring — including VRF dice rolls and proof verification.

## Related Repos

- [autoloop-worker](https://github.com/LuckyMachines/autoloop-worker) — Off-chain worker bot with VRF proof generation
- [autoloop-dashboard](https://github.com/LuckyMachines/autoloop-dashboard) — Web-based control panel and event monitor
