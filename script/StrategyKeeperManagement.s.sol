// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

contract StrategyKeeperManagement is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        uint256 keeperAddress = vm.envAddress("KEEPER_ADDRESS");
        address strategy = vm.envAddress("STRATEGY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");
        
        vm.startBroadcast(deployerPK);
        ITokenizedStrategy(strategy).setKeeper(keeperAddress);
        console.log("accepted management");
        vm.stopBroadcast();
    }
}