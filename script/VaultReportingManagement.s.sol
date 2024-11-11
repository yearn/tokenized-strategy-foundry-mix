// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@yearn-vaults/interfaces/IVault.sol";


contract VaultReportingManagement is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        address keeperAddress = vm.envAddress("KEEPER_ADDRESS");
        address vault = vm.envAddress("VAULT");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");
        
        vm.startBroadcast(deployerPK);
        IVault(vault).add_role(keeperAddress, 32);
        console.log("keeper given reporting role");
        vm.stopBroadcast();
    }
}