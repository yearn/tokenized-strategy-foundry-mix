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

        address deployer = vm.addr(deployerPK);

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY");
        address accountantFactoryAddress = vm.envAddress("ACCOUNTANT_FACTORY");
        address asset = vm.envAddress("ASSET_ADDRESS");
        string memory name = vm.envString("VAULT_NAME");
        string memory symbol = vm.envString("VAULT_SYMBOL");
        uint256 profitMaxUnlockTime = vm.envUint("PROFIT_MAX_UNLOCK_TIME");
        address vaultGovernanceFactory = vm.envAddress("VAULT_GOVERNANCE_FACTORY");

        IVaultFactory vaultFactory = IVaultFactory(vaultFactoryAddress);
        address vaultAddress = vaultFactory.deploy_new_vault(asset, name, symbol, deployer, profitMaxUnlockTime);
        IVault vault = IVault(vaultAddress);
        console.log("deployed vault contract to");
        console.log(address(vault));

        AccountantFactory accountantFactory = AccountantFactory(accountantFactoryAddress);
        address accountantAddress = accountantFactory.newAccountant();
        Accountant accountant = Accountant(accountantAddress);
        console.log("deployed accountant contract to");
        console.log(address(accountant));

        _setVaultParams(vault, accountantAddress, vaultGovernanceFactory);
        _setAccountantParams(accountant, vaultGovernanceFactory);

        vm.stopBroadcast();
    }

    function _setVaultParams(IVault vault, address accountant, address vaultGovernanceFactory) internal {
        uint256 depositLimit = vm.envOr("DEPOSIT_LIMIT",uint256(0));
        address keeper = vm.envAddress("KEEPER_ADDRESS");

        vault.set_role(keeper, 112);
        console.log("set role for keeper");

        vault.set_accountant(accountant);
        console.log("set accountant for vault");
        console.log(accountant);

        vault.set_deposit_limit(depositLimit);
        console.log("set deposit limit");
        console.log(depositLimit);

        vault.set_use_default_queue(true);
        console.log("set use default queue to true");
        vault.set_auto_allocate(true);
        console.log("set auto allocate to true");

        vault.transfer_role_manager(vaultGovernanceFactory);
        vault.accept_role_manager();
    }

    function _setAccountantParams(Accountant accountant, address vaultGovernanceFactory) internal {
        uint16 defaultPerformance = uint16(vm.envOr("DEFAULT_PERFORMANCE", uint256(0)));
        uint16 defaultMaxFee = uint16(vm.envOr("DEFAULT_MAX_FEE", uint256(0)));
        uint16 defaultMaxGain = uint16(vm.envOr("DEFAULT_MAX_GAIN", uint256(0)));
        uint16 defaultMaxLoss = uint16(vm.envOr("DEFAULT_MAX_LOSS", uint256(0)));
        address newFeeRecipient = vm.envAddress("FEE_RECIPIENT");

        accountant.updateDefaultConfig(uint16(0), defaultPerformance, uint16(0), defaultMaxFee, defaultMaxGain, defaultMaxLoss);
        console.log("set default config for accountant");
        console.log("default performance");
        console.log(defaultPerformance);
        console.log("default max fee");
        console.log(defaultMaxFee);
        console.log("default max gain");
        console.log(defaultMaxGain);
        console.log("default max loss");
        console.log(defaultMaxLoss);

        accountant.setFutureFeeManager(vaultGovernanceFactory);
        console.log("set future fee manager");
        console.log(vaultGovernanceFactory);

        accountant.setFeeRecipient(newFeeRecipient);
        console.log("set fee recipient");
        console.log(newFeeRecipient);
    }
}
