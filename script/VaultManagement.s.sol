// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "@yearn-vaults/interfaces/IVault.sol";
import "@yearn-vaults/interfaces/IVaultFactory.sol";
import "vault-periphery/contracts/accountants/Accountant.sol";
import "vault-periphery/contracts/accountants/AccountantFactory.sol";

contract SetupVaultManagement is Script {
    // Declare state variables to reduce stack depth
    IVault public vault;
    Accountant public accountant;
    address public deployer;
    address public vaultGovernanceFactory;

    function run() external {
        _setupInitialVariables();
        _deployVault();
        _deployAccountant();
        _configureVault();
        _configureAccountant();
        vm.stopBroadcast();
    }

    function _setupInitialVariables() internal {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPK);
        vm.startBroadcast(deployerPK);
        vaultGovernanceFactory = vm.envAddress("VAULT_GOVERNANCE_FACTORY");
    }

    function _deployVault() internal {
        address vaultFactoryAddress = vm.envAddress("VAULT_FACTORY");
        address asset = vm.envAddress("ASSET_ADDRESS");
        string memory name = vm.envString("VAULT_NAME");
        string memory symbol = vm.envString("VAULT_SYMBOL");
        uint256 profitMaxUnlockTime = vm.envUint("PROFIT_MAX_UNLOCK_TIME");

        IVaultFactory vaultFactory = IVaultFactory(vaultFactoryAddress);
        address vaultAddress = vaultFactory.deploy_new_vault(
            asset,
            name,
            symbol,
            deployer,
            profitMaxUnlockTime
        );
        vault = IVault(vaultAddress);
        console.log("deployed vault contract to", address(vault));
    }

    function _deployAccountant() internal {
        address accountantFactoryAddress = vm.envAddress("ACCOUNTANT_FACTORY");
        AccountantFactory accountantFactory = AccountantFactory(accountantFactoryAddress);
        address accountantAddress = accountantFactory.newAccountant();
        accountant = Accountant(accountantAddress);
        console.log("deployed accountant contract to", address(accountant));
    }

    function _configureVault() internal {
        address keeper = vm.envAddress("KEEPER_ADDRESS");
        uint256 depositLimit = vm.envOr("DEPOSIT_LIMIT", uint256(0));

        // Set deployer roles
        vault.set_role(deployer, 16383);

        // Set keeper roles (QUEUE_MANAGER | REPORTING_MANAGER | DEBT_MANAGER = 112)
        vault.set_role(keeper, 112);
        console.log("set role for keeper");

        // Configure vault parameters
        vault.set_accountant(address(accountant));
        console.log("set accountant for vault", address(accountant));

        vault.set_deposit_limit(depositLimit);
        console.log("set deposit limit", depositLimit);

        vault.set_use_default_queue(true);
        console.log("set use default queue to true");

        // Transfer management
        _transferVaultManagement();
    }

    function _transferVaultManagement() internal {
        vault.transfer_role_manager(vaultGovernanceFactory);
        vault.set_role(deployer, 0);
    }

    function _configureAccountant() internal {
        // Load fee parameters
        uint16 defaultPerformance = uint16(vm.envOr("DEFAULT_PERFORMANCE", uint256(0)));
        uint16 defaultMaxFee = uint16(vm.envOr("DEFAULT_MAX_FEE", uint256(0)));
        uint16 defaultMaxGain = uint16(vm.envOr("DEFAULT_MAX_GAIN", uint256(0)));
        uint16 defaultMaxLoss = uint16(vm.envOr("DEFAULT_MAX_LOSS", uint256(0)));
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        // Set accountant parameters
        accountant.updateDefaultConfig(
            0, // default management
            defaultPerformance,
            0, // default refund
            defaultMaxFee,
            defaultMaxGain,
            defaultMaxLoss
        );

        console.log("set default config for accountant");
        console.log("default performance", defaultPerformance);
        console.log("default max fee", defaultMaxFee);
        console.log("default max gain", defaultMaxGain);
        console.log("default max loss", defaultMaxLoss);

        accountant.addVault(address(vault));

        accountant.setFutureFeeManager(vaultGovernanceFactory);
        console.log("set future fee manager", vaultGovernanceFactory);

        accountant.setFeeRecipient(feeRecipient);
        console.log("set fee recipient", feeRecipient);
    }
}