// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "@yearn-vaults/interfaces/IVault.sol";
import "@yearn-vaults/interfaces/IVaultFactory.sol";
import "vault-periphery/contracts/accountants/Accountant.sol";
import "vault-periphery/contracts/accountants/AccountantFactory.sol";

contract VaultStrategySwitch is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address yearnVaultAddress = vm.envAddress("YEARN_VAULT_ADDRESS");
        address newStrategy = vm.envAddress("NEW_STRATEGY_ADDRESS");
        address oldStrategy = vm.envOr("OLD_STRATEGY_ADDRESS", address(0));

        address[] memory strategies = new address[](1);
        strategies[0] = newStrategy;

        IVault vault = IVault(yearnVaultAddress);
        vault.add_strategy(newStrategy);
        console.log("added strategy to vault");
        console.log(newStrategy);
        vault.set_default_queue(strategies);
        console.log("set default queue for vault");


        if (oldStrategy != address(0)) {
            vault.update_debt(oldStrategy, 0);
            console.log("updated debt for old strategy to 0");
            console.log(oldStrategy);

            vault.revoke_strategy(oldStrategy);
            console.log("revoked strategy from vault");
            console.log(oldStrategy);

            vault.set_default_queue(strategies);
            console.log("set default queue for vault");
        }        
        vm.stopBroadcast();
    }
}
