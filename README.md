# YieldNest Delta Neutral Strategy

`ynDeltaNTRL` is a Solidity implementation of a delta-neutral yield strategy using ynETHx, ynBTCx, and ynUSDx yield-bearing tokens.

## Overview

This project implements a delta-neutral yield strategy that:

1. Earns yield from yield-bearing assets (ynETHx, ynBTCx, and ynUSDx)
2. Maintains delta neutrality by offsetting crypto exposure with hedging
3. Automates rebalancing to maintain neutral exposure and optimize returns

## Project Structure

```
├── src
│   ├── DeltaNeutralStrategy.sol        # Main strategy contract
│   ├── interfaces
│   │   ├── IDeltaNeutralStrategy.sol   # Strategy interface
│   │   ├── IYieldToken.sol             # Interface for yield tokens
│   │   ├── IHedgingPlatform.sol        # Interface for hedging platforms
│   │   └── IYieldProtocol.sol          # Interface for yield protocols
├── test
│   └── DeltaNeutralStrategy.t.sol      # Strategy tests with mocks
```

## How It Works

### 1. Yield Generation
- Users deposit ETH, BTC, and stablecoins (USDC/DAI) to get yield-bearing tokens (ynETHx, ynBTCx, ynUSDx)
- These yield-bearing tokens automatically accrue yield over time

### 2. Delta Neutrality
- The strategy creates short positions to hedge against price exposure from ynETHx and ynBTCx
- This ensures the portfolio value remains stable regardless of crypto price movements

### 3. Rebalancing
- The contract monitors the net exposure of the portfolio
- When exposure deviates beyond a threshold, the strategy automatically rebalances by adjusting hedge positions

### 4. Stablecoin Yield Optimization
- Stablecoins can be deployed to approved yield protocols to maximize returns

## Key Features

- **Automated Hedging**: Automatically creates and adjusts hedge positions
- **Portfolio Management**: Tracks positions and calculates net exposure
- **Yield Optimization**: Deploys stablecoins to the best yield sources
- **APR Estimation**: Calculates estimated returns based on current positions

## How to Build and Test

### Prerequisites
- [Foundry](https://getfoundry.sh/)

### Building
```bash
forge build
```

### Testing
```bash
forge test
```

## Configurable Parameters

- **Target Allocations**: Configure portfolio allocation between ETH, BTC, and USD exposure
- **Rebalance Threshold**: Set the deviation threshold that triggers rebalancing
- **Slippage Tolerance**: Maximum acceptable slippage for trades

## Security Considerations

- **Liquidation Risk**: The strategy includes protection against over-leveraging
- **Funding Rate Risk**: Accounts for funding rates in short positions
- **Governance Controls**: Key parameters can only be modified by the contract owner

## Expected Returns

| Component | Estimated APR |
|-----------|---------------|
| ynETHx Staking Yield | 3-6% |
| ynBTCx Yield | 2-5% |
| ynUSDx Yield | 4-8% |
| Hedging Costs (Shorts) | (-1 to -3%) |
| Net Estimated APR | 7-16% |


## Detailed Strategy

For a detailed explanation of the strategy, including:
- Portfolio construction with yield-bearing assets
- Delta neutrality through hedging
- Automated rebalancing mechanism
- Risk considerations and expected returns

See [Strategy.md](./Strategy.md)

