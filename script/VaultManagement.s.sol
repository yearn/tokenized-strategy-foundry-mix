// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "@yearn-vaults/interfaces/IVault.sol";
import "@yearn-vaults/interfaces/IVaultFactory.sol";
import "vault-periphery/contracts/accountants/Accountant.sol";
import "vault-periphery/contracts/accountants/AccountantFactory.sol";

contract SetupVaultManagement is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY");
        address accountantFactoryAddress = vm.envAddress("ACCOUNTANT_FACTORY");
        address asset = vm.envAddress("ASSET_ADDRESS");
        string memory name = vm.envString("VAULT_NAME");
        string memory symbol = vm.envString("VAULT_SYMBOL");
        address roleManager = vm.envAddress("ROLE_MANAGER");
        uint256 profitMaxUnlockTime = vm.envUint("PROFIT_MAX_UNLOCK_TIME");
        address feeManager = vm.envAddress("FEE_MANAGER");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 depositLimit = vm.envOr("DEPOSIT_LIMIT",uint256(0));

        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 roleNum = vm.envOr("ROLE_NUM", uint(256));
        bool isTest = vm.envBool("IS_TEST");

        IVaultFactory vaultFactory = IVaultFactory(vaultFactoryAddress);
        address vaultAddress = vaultFactory.deploy_new_vault(asset, name, symbol, roleManager, profitMaxUnlockTime);
        IVault vault = IVault(vaultAddress);
        console.log("deployed vault contract to");
        console.log(address(vault));

        AccountantFactory accountantFactory = AccountantFactory(accountantFactoryAddress);
        address accountantAddress = accountantFactory.newAccountant(feeManager, feeRecipient);
        Accountant accountant = Accountant(accountantAddress);
        console.log("deployed accountant contract to");
        console.log(address(accountant));

        if (isTest) {
            vault.set_role(admin, roleNum);
            console.log("set role for admin");
            console.log(roleNum);

            vault.set_accountant(address(accountant));
            console.log("set accountant for vault");
            console.log(address(accountant));


            vault.set_deposit_limit(depositLimit);
            console.log("set deposit limit");
            console.log(depositLimit);

            vault.set_use_default_queue(true);
            console.log("set use default queue to true");
            vault.set_auto_allocate(true);
            console.log("set auto allocate to true");
        }
        
        vm.stopBroadcast();
    }
}
