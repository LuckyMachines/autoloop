# AutoLoop Template Contracts

Ready-to-use templates for building AutoLoop-compatible contracts.

## Templates

### TimeBasedTrigger
Fires at a fixed interval (e.g., every hour, every day). Extend and override `_onLoop()`.

### PriceOracleTrigger
Fires when a Chainlink price feed crosses a threshold. Tracks above/below state to fire once per crossing. Extend and override `_onPriceCrossing(bool isAbove)`.

### BalanceWatcher
Fires when an address's ETH balance drops below a minimum. Extend and override `_onBalanceLow(uint256 currentBalance)`.

## Usage

1. Import the template in your contract
2. Override the abstract function with your logic
3. Deploy and register with AutoLoop

```solidity
import "../templates/TimeBasedTrigger.sol";

contract MyHourlyTask is TimeBasedTrigger {
    constructor() TimeBasedTrigger(3600) {}

    function _onLoop() internal override {
        // Your hourly logic here
    }
}
```

## Deployment

```bash
forge create templates/TimeBasedTrigger.sol:TimeBasedTrigger --constructor-args 3600
```
