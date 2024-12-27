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
  }

  private async setupInitialVariables() {
    this.deployer = await this.managedSigner.getAddress();
    this.vaultGovernanceFactory = process.env.VAULT_GOVERNANCE_FACTORY!;
  }

  private async deployVault() {
    const vaultFactoryAddress = process.env.VAULT_FACTORY!;
    const asset = process.env.ASSET_ADDRESS!;
    const name = process.env.VAULT_NAME!;
    const symbol = process.env.VAULT_SYMBOL!;
    const profitMaxUnlockTime = process.env.PROFIT_MAX_UNLOCK_TIME!;

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
    const receipt = await tx.wait();

    // Get the vault address from the deployment event
    const vaultAddress = receipt.events?.[0].args?.vault;
    this.vault = await ethers.getContractAt("IVault", vaultAddress, this.managedSigner);
    console.log("Deployed vault contract to:", this.vault.address);
  }

  private async deployAccountant() {
    const accountantFactoryAddress = process.env.ACCOUNTANT_FACTORY!;
    const accountantFactory = await ethers.getContractAt(
      "AccountantFactory",
      accountantFactoryAddress,
      this.managedSigner
    );

    const tx = await accountantFactory.newAccountant();
    const receipt = await tx.wait();

    // Get the accountant address from the deployment event
    const accountantAddress = receipt.events?.[0].args?.accountant;
    this.accountant = await ethers.getContractAt("Accountant", accountantAddress, this.managedSigner);
    console.log("Deployed accountant contract to:", this.accountant.address);
  }

  private async configureVault() {
    const keeper = process.env.KEEPER_ADDRESS!;
    const strategyAdder = process.env.STRATEGY_ADDER!;
    const depositLimit = process.env.DEPOSIT_LIMIT || "0";

    // Set deployer roles
    await (await this.vault.set_role(this.deployer, 16383)).wait();

    // Set keeper roles (QUEUE_MANAGER | REPORTING_MANAGER | DEBT_MANAGER = 112)
    await (await this.vault.set_role(keeper, 112)).wait();
    console.log("Set role for keeper");

    // Configure vault parameters
    await (await this.vault.set_accountant(this.accountant.address)).wait();
    console.log("Set accountant for vault:", this.accountant.address);

    await (await this.vault.set_deposit_limit(depositLimit)).wait();
    console.log("Set deposit limit:", depositLimit);

    await (await this.vault.set_use_default_queue(true)).wait();
    console.log("Set use default queue to true");

    await (await this.vault.set_role(strategyAdder, 193)).wait();

    // Transfer management
    await this.transferVaultManagement();
  }

  private async transferVaultManagement() {
    await (await this.vault.transfer_role_manager(this.vaultGovernanceFactory)).wait();
    await (await this.vault.set_role(this.deployer, 0)).wait();
  }

  private async configureAccountant() {
    const defaultPerformance = process.env.DEFAULT_PERFORMANCE || "0";
    const defaultMaxFee = process.env.DEFAULT_MAX_FEE || "0";
    const defaultMaxGain = process.env.DEFAULT_MAX_GAIN || "0";
    const defaultMaxLoss = process.env.DEFAULT_MAX_LOSS || "0";
    const feeRecipient = process.env.FEE_RECIPIENT!;

    // Set accountant parameters
    await (await this.accountant.updateDefaultConfig(
      0, // default management
      defaultPerformance,
      0, // default refund
      defaultMaxFee,
      defaultMaxGain,
      defaultMaxLoss
    )).wait();

    console.log("Set default config for accountant");
    console.log("Default performance:", defaultPerformance);
    console.log("Default max fee:", defaultMaxFee);
    console.log("Default max gain:", defaultMaxGain);
    console.log("Default max loss:", defaultMaxLoss);

    await (await this.accountant.addVault(this.vault.address)).wait();

    await (await this.accountant.setFutureFeeManager(this.vaultGovernanceFactory)).wait();
    console.log("Set future fee manager:", this.vaultGovernanceFactory);

    await (await this.accountant.setFeeRecipient(feeRecipient)).wait();
    console.log("Set fee recipient:", feeRecipient);
  }

  public async run() {
    await this.setupInitialVariables();
    await this.deployVault();
    await this.deployAccountant();
    await this.configureVault();
    await this.configureAccountant();
  }
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const managedSigner = new NonceManager(deployer as any) as unknown as Signer;

  const setup = new SetupVaultManagement(managedSigner);
  await setup.run();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });