// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/helper/TermVaultsKeeper.sol";
import "forge-std/Script.sol";

contract TermVaultsKeeperDeployer is Script {
    function run() external {
        // Load environment variables
        address devops = vm.envAddress("DEVOPS_ADDRESS"); // Replace with actual devops address from env variable
        address initialKeeper = vm.envAddress("INITIAL_KEEPER_ADDRESS"); // Replace with actual initial keeper address from env variable
        bool implOnly = vm.envBool("IMPL_ONLY");
        address implementation = address(new TermVaultsKeeper());

        if (!implOnly) {
            // Deploy ERC1967 proxy contract
            ERC1967Proxy proxy = new ERC1967Proxy(implementation, abi.encodeWithSelector(TermVaultsKeeper.initialize.selector, devops, initialKeeper));
            console.log("Proxy deployed at:", address(proxy));
            console.log("Implementation deployed at:", implementation);
        }
    }
}