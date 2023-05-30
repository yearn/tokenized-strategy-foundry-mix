// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";

contract OracleTest is Setup {
    StrategyAprOracle public oracle;

    function setUp() public override {
        super.setUp();
        oracle = new StrategyAprOracle();
    }

    function checkOracle(address _strategy, uint256 _delta) public {
        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");

        // DONE: Uncomment to test the apr goes up and down based on debt changes
        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            -int256(_delta)
        );
        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            int256(_delta)
        );

        assertLt(currentApr, negativeDebtChangeApr, "negative change");
        assertGt(currentApr, positiveDebtChangeApr, "positive change");
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        // amount must be high enough to move aave rates
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: adjust the number to base _perfenctChange off of.
        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        console.log("delta", _delta);
        console.log("amount", _amount);
        checkOracle(address(strategy), _delta);
    }

    // TODO: Deploy multiple strategies with differen tokens as `asset` to test against the oracle.
}
