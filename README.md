# Tokenized Strategy Mix for Yearn V3 strategies

This repo will allow you to write, test and deploy V3 "Tokenized Strategies" using [Foundry](https://book.getfoundry.sh/).

You will only need to override the three functions in Strategy.sol of `_deployFunds`, `_freeFunds` and `_harvestAndReport`. With the option to also override `_tend`, `tendTrigger`, `availableDepositLimit`, `availableWithdrawLimit` and `_emegencyWithdraw` if desired.

For a more complete overview of how the Tokenized Strategies work please visit the [TokenizedStrategy Repo](https://github.com/yearn/tokenized-strategy).

## How to start

### Requirements

First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Fork this repository

```sh
git clone --recursive https://github.com/user/tokenized-strategy-foundry-mix

cd tokenized-strategy-foundry-mix

yarn
```

### Set your environment Variables

Sign up for [Infura](https://infura.io/) and generate an API key and copy your RPC url. Store it in the `ETH_RPC_URL` environment variable.
NOTE: you can use other services.

Use .env file

1. Make a copy of `.env.example`
2. Add the values for `ETH_RPC_URL`, `ETHERSCAN_API_KEY` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

### Build the project

```sh
make build
```

Run tests

```sh
make test
```

## Strategy Writing

### Good to know

To create your tokenized Strategy, you must override at least 3 functions outlined in `Strategy.sol`. An in-depth description for each function is provided above each function in `Strategy.sol`.

It is important to remember the default behavior for any tokenized strategy is to be a permissionless vault, so functions such as _deployFunds and _freeFunds can be called by anyone, and care should be taken when implementing manipulatable logic such as swaps/LP movements. Strategists can choose to limit deposit/withdraws by overriding the `availableWithdrawLimit` and `availableDepositLimit` function if it is needed for safety.

It is recommended to build strategies on the assumption that reports will happen based on the strategies specific `profitMaxUnlockTime`. Since this is the only time _harvestAndReport will be called any strategies that need more frequent checks or updates should override the _tend and tendTrigger functions for any needed mid-report maintenance.

The only default global variables from the BaseTokenizedStrategy that can be accessed from storage is `asset` and `TokenizedStrategy`. If other global variables are needed for your specific strategy, you can use the `TokenizedStrategy` variable to quickly retrieve any other needed variables within the strategy, such as totalAssets, totalDebt, isShutdown etc.

Example:

    require(!TokenizedStrategy.isShutdown(), "strategy is shutdown");

NOTE: It is impossible to write to a strategy's default global storage state internally post-deployment. You must make external calls from the `management` address to configure any of the desired variables.

To include permissioned functions such as extra setters, the two modifiers of `onlyManagement` and `onlyManagementAndKeepers` are available by default.

For strategies that will be used with multiple different asset's it is recommended to build a factory, that can be deployed once and then all strategies can be deployed on chain. Cloning is not recommended for Tokenized Strategies.

The symbol used for each tokenized Strategy is set automatically with a standardized approach based on the `asset`'s symbol. Strategists should use the `name` parameter in the constructor for a unique and descriptive name that encapsulates their specific Strategy. Standard naming conventions will include the asset name, the protocol used to generate yield, and the method rewards are sold if applicable. I.e., "Weth-AaveV3Lender-UniV3Swapper".

There is an optional `_emergencyWithdraw` function that can be overridden to specify logic to remove funds from the strategy specific yield source in an emergency. This function can only be used if a strategy is shutdown. It is meant to simply withdraw funds and keep them idle in the strategy to service withdraws.

All other functionality, such as reward selling, upgradability, etc., is up to the strategist to determine what best fits their vision. Due to the ability of strategies to stand alone from a Vault, it is expected and encouraged for strategists to experiment with more complex, risky, or previously unfeasible Strategies.

## Periphery

To make Strategy writing as simple as possible, a suite of optional 'Periphery Helper' contracts can be inherited by your Strategy to provide standardized and tested functionality for things like swaps. A complete list of the periphery contracts can be viewed here https://github.com/Schlagonia/tokenized-strategy-periphery.

All periphery contracts are optional, and strategists are free to choose if they wish to use them.

### Swappers

In order to make reward swapping as easy and standardized as possible there are multiple swapper contracts that can be inherited by a strategy to inherit pre-built and tested logic for whichever method of reward swapping is desired. This allows a strategist to only need to set a few global variables and then simply use the default syntax of `_swapFrom(tokenFrom, tokenTo, amount, minAmountOut)` to swap any tokens easily during `_harvestAndReport`.

### APR Oracles

In order for easy integration with Vaults, front ends, debt allocators etc. There is the option to create an APR oracle contract for your specific strategy that should return the expected APR of the Strategy based on some given `debtChange`. 

### HealthCheck

In order to prevent automated reports from reporting losses/excessive profits from automated reports that may not be accurate, a strategist can inherit and implement the HealtCheck contract. Using this can assure that a keeper will not call a report that may incorrectly realize incorrect losses or excessive gains. It can cause the report to revert if the gain/loss is outside of the desired bounds and will require manual intervention to assure the strategy is reporting correctly.

NOTE: It is recommended to implement some checks in `_harvestAndReport` for leveraged or manipulatable strategies that could report incorrect losses due to unforeseen circumstances.

### Report Triggers

The expected behavior is that strategies report profits/losses on a set schedule based on their specific `profitMaxUnlockTime` that management can customize. If a custom trigger cycle is desired or extra checks should be added a strategist can create their own customReportTrigger that can be added to the default contract for a specific strategy.

## Testing

Due to the nature of the BaseTokenizedStrategy utilizing an external contract for the majority of its logic, the default interface for any tokenized strategy will not allow proper testing of all functions. Testing of your Strategy should utilize the pre-built [IStrategyInterface](https://github.com/Schlagonia/tokenized-strategy-foundry-mix/blob/master/src/interfaces/IStrategyInterface.sol) to cast any deployed strategy through for testing, as seen in the Setup example. You can add any external functions that you add for your specific strategy to this interface to be able to test all functions with one variable. 

Example:

```solidity
Strategy _strategy = new Strategy(asset, name);
IStrategyInterface strategy =  IStrategyInterface(address(_strategy));
```

Due to the permissionless nature of the tokenized Strategies, all tests are written without integration with any meta vault funding it. While those tests can be added, all V3 vaults utilize the ERC-4626 standard for deposit/withdraw and accounting, so they can be plugged in easily to any number of different vaults with the same `asset.`

Tests run in fork environment, you need to complete the full installation and setup to be able to run these commands.

```sh
make test
```

Run tests with traces (very useful)

```sh
make trace
```

Run specific test contract (e.g. `test/StrategyOperation.t.sol`)

```sh
make test-contract contract=StrategyOperationsTest
```

Run specific test contract with traces (e.g. `test/StrategyOperation.t.sol`)

```sh
make trace-contract contract=StrategyOperationsTest
```

See here for some tips on testing [`Testing Tips`](https://book.getfoundry.sh/forge/tests.html)

When testing on chains other than mainnet you will need to make sure a valid `CHAIN_RPC_URL` for that chain is set in your .env and that chain's specific api key is set for `ETHERSCAN_API_KEY`. You will then need to simply adjust the variable that RPC_URL is set to in the Makefile to match your chain.

### Errors

To update to a new API version of the TokenizeStrategy you will need to simply remove and reinstall the dependency.

```sh
git rm -r lib/tokenized-strategy/

forge install yearn/tokenized-strategy@API_VERSION
```

### Deployment

#### Contract Verification

Once the Strategy is fully deployed and verified, you will need to verify the TokenizedStrategy functions. To do this, navigate to the /#code page on Etherscan.

1. Click on the `More Options` drop-down menu
2. Click "is this a proxy?"
3. Click the "Verify" button
4. Click "Save"

This should add all of the external `TokenizedStrategy` functions to the contract interface on Etherscan.

See the ApeWorx [documentation](https://docs.apeworx.io/ape/stable/) and [GitHub](https://github.com/ApeWorX/ape) for more information.
