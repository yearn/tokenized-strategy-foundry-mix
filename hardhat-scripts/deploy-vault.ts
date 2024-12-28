import { ethers, run } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { NonceManager } from "@ethersproject/experimental";
import dotenv from "dotenv";
import { Signer } from "ethers";
import { Contract } from "ethers";

dotenv.config();

class SetupVaultManagement {
  private vault: Contract;
  private accountant: Contract;
  private deployer: string;
  private vaultGovernanceFactory: string;
  private managedSigner: Signer;

  constructor(managedSigner: Signer) {
    this.managedSigner = managedSigner;
    console.log("SetupVaultManagement initialized with managed signer");
  }

  private async setupInitialVariables() {
    console.log("Setting up initial variables...");
    this.deployer = await this.managedSigner.getAddress();
    console.log("Deployer address:", this.deployer);

    this.vaultGovernanceFactory = process.env.VAULT_GOVERNANCE_FACTORY!;
    console.log("Vault governance factory address:", this.vaultGovernanceFactory);
  }

  private async deployVault() {
    console.log("Deploying vault...");
    const vaultFactoryAddress = process.env.VAULT_FACTORY!;
    const asset = process.env.ASSET_ADDRESS!;
    const name = process.env.VAULT_NAME!;
    const symbol = process.env.VAULT_SYMBOL!;
    const profitMaxUnlockTime = process.env.PROFIT_MAX_UNLOCK_TIME!;

    console.log("Vault factory address:", vaultFactoryAddress);
    console.log("Asset address:", asset);
    console.log("Vault name:", name);
    console.log("Vault symbol:", symbol);
    console.log("Profit max unlock time:", profitMaxUnlockTime);

    const vaultFactory = await ethers.getContractAt(
      "IVaultFactory",
      vaultFactoryAddress,
      this.managedSigner
    );

    const tx = await vaultFactory.deploy_new_vault(
      asset,
      name,
      symbol,
      this.deployer,
      profitMaxUnlockTime
    );
    console.log("Vault deployment transaction sent, waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("Transaction receipt:", receipt);
    console.log("Events:", receipt.events);

        // Locate the event that contains the vault address
    const deployEvent = receipt.events?.find((event) => event.event === "NewVault");
    if (!deployEvent || !deployEvent.args) {
    throw new Error("VaultDeployed event not found or missing args");
    }

    // Extract the vault address
    const vaultAddress = deployEvent.args.vaultAddress;
    console.log("Deployed vault address:", vaultAddress);

    console.log("Vault deployed at address:", vaultAddress);

    this.vault = await ethers.getContractAt("IVault", vaultAddress, this.managedSigner);
  }

  private async deployAccountant() {
    console.log("Deploying accountant...");
    const accountantFactoryAddress = process.env.ACCOUNTANT_FACTORY!;
    console.log("Accountant factory address:", accountantFactoryAddress);

    const accountantFactory = await ethers.getContractAt(
      "AccountantFactory",
      accountantFactoryAddress,
      this.managedSigner
    );

    const tx = await accountantFactory.newAccountant();
    console.log("Accountant deployment transaction sent, waiting for confirmation...");
    const receipt = await tx.wait();

    console.log("Transaction receipt:", receipt);
    console.log("Events:", receipt.events);

        // Locate the event that contains the vault address
    const deployEvent = receipt.events?.find((event) => event.event === "NewAccountant");
    if (!deployEvent || !deployEvent.args) {
    throw new Error("VaultDeployed event not found or missing args");
    }

    // Extract the vault address
    const accountantAddress = deployEvent.args.newAccountant;

    console.log("Accountant deployed at address:", accountantAddress);

    this.accountant = await ethers.getContractAt("Accountant", accountantAddress, this.managedSigner);
  }

  private async configureVault() {
    console.log("Configuring vault...");
    const keeper = process.env.KEEPER_ADDRESS!;
    const strategyAdder = process.env.STRATEGY_ADDER!;
    const depositLimit = process.env.DEPOSIT_LIMIT || "0";

    console.log("Keeper address:", keeper);
    console.log("Strategy adder address:", strategyAdder);
    console.log("Deposit limit:", depositLimit);

    console.log("Setting deployer role...");
    await (await this.vault.set_role(this.deployer, 16383)).wait();
    console.log("Deployer role set.");

    console.log("Setting keeper roles...");
    await (await this.vault.set_role(keeper, 112)).wait();
    console.log("Keeper roles set.");

    console.log("Configuring vault parameters...");
    await (await this.vault.set_accountant(this.accountant.address)).wait();
    console.log("Accountant set for vault:", this.accountant.address);

    await (await this.vault.set_deposit_limit(depositLimit)).wait();
    console.log("Deposit limit set:", depositLimit);

    await (await this.vault.set_use_default_queue(true)).wait();
    console.log("Default queue set to true.");

    await (await this.vault.set_role(strategyAdder, 193)).wait();
    console.log("Strategy adder role set.");

    console.log("Transferring vault management...");
    await this.transferVaultManagement();
  }

  private async transferVaultManagement() {
    console.log("Transferring role manager to vault governance factory...");
    await (await this.vault.transfer_role_manager(this.vaultGovernanceFactory)).wait();
    console.log("Role manager transferred.");

    console.log("Removing deployer roles...");
    await (await this.vault.set_role(this.deployer, 0)).wait();
    console.log("Deployer roles removed.");
  }

  private async configureAccountant() {
    console.log("Configuring accountant...");
    const defaultPerformance = process.env.DEFAULT_PERFORMANCE || "0";
    const defaultMaxFee = process.env.DEFAULT_MAX_FEE || "0";
    const defaultMaxGain = process.env.DEFAULT_MAX_GAIN || "0";
    const defaultMaxLoss = process.env.DEFAULT_MAX_LOSS || "0";
    const feeRecipient = process.env.FEE_RECIPIENT!;

    console.log("Default performance:", defaultPerformance);
    console.log("Default max fee:", defaultMaxFee);
    console.log("Default max gain:", defaultMaxGain);
    console.log("Default max loss:", defaultMaxLoss);
    console.log("Fee recipient:", feeRecipient);

    console.log("Updating accountant default config...");
    await (await this.accountant.updateDefaultConfig(
      0, // default management
      defaultPerformance,
      0, // default refund
      defaultMaxFee,
      defaultMaxGain,
      defaultMaxLoss
    )).wait();
    console.log("Default config updated.");

    console.log("Adding vault to accountant...");
    await (await this.accountant.addVault(this.vault.address)).wait();
    console.log("Vault added to accountant:", this.vault.address);

    console.log("Setting future fee manager...");
    await (await this.accountant.setFutureFeeManager(this.vaultGovernanceFactory)).wait();
    console.log("Future fee manager set:", this.vaultGovernanceFactory);

    console.log("Setting fee recipient...");
    await (await this.accountant.setFeeRecipient(feeRecipient)).wait();
    console.log("Fee recipient set:", feeRecipient);
  }

  public async run() {
    console.log("Starting setup process...");
    await this.setupInitialVariables();
    await this.deployVault();
    await this.deployAccountant();
    await this.configureVault();
    await this.configureAccountant();
    console.log("Setup process complete.");
  }
}

async function main() {
  console.log("Initializing deployment...");
  const [deployer] = await ethers.getSigners();
  console.log("Deployer signer obtained:", await deployer.getAddress());

  const managedSigner = new NonceManager(deployer as any) as unknown as Signer;
  console.log("NonceManager initialized.");

  const setup = new SetupVaultManagement(managedSigner);
  await setup.run();
}

main()
  .then(() => {
    console.log("Script executed successfully.");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Error occurred during setup:", error);
    process.exit(1);
  });
