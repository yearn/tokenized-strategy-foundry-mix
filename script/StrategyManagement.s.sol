// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract StrategyManagement is Script {
    function run() external {
        uint256 strategyManagement = vm.envUint("STRATEGY_MANAGEMENT_ADDRESS");
        address strategy = vm.envAddress("STRATEGY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");
        
        vm.startBroadcast(strategyManagement);
        ITokenizedStrategy(strategy).acceptManagement();
        console.log("accepted management");
        vm.stopBroadcast();


    }
}