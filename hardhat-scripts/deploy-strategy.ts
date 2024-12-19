import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { NonceManager } from "@ethersproject/experimental";
import dotenv from "dotenv";
import { Signer } from "ethers";

dotenv.config();

function stringToAddressArray(input: string): string[] {
  if (!input) return [];
  return input.split(",").map((addr) => {
    const trimmed = addr.trim();
    if (!hre.ethers.isAddress(trimmed)) {
      throw new Error(`Invalid address: ${trimmed}`);
    }
    return trimmed;
  });
}

function stringToUintArray(input: string): number[] {
  if (!input) return [];
  return input.split(",").map((num) => {
    const trimmed = num.trim();
    const parsed = parseInt(trimmed);
    if (isNaN(parsed) || parsed.toString() !== trimmed) {
      throw new Error(`Invalid number: ${trimmed}`);
    }
    return parsed;
  });
}

async function checkUnderlyingVaultAsset(
  asset: string,
  underlyingVault: string,
  managedSigner: Signer
) {
  const vault = await hre.ethers.getContractAt(
    "IERC4626",
    underlyingVault,
    managedSigner
  );
  const underlyingAsset = await vault.asset();
  if (underlyingAsset.toLowerCase() !== asset.toLowerCase()) {
    throw new Error("Underlying asset does not match asset");
  }
}

async function buildStrategyParams(
  eventEmitter: string,
  deployer: string,
  managedSigner: Signer
) {
  const asset = process.env.ASSET_ADDRESS!;
  const yearnVaultAddress = process.env.YEARN_VAULT_ADDRESS!;
  const discountRateAdapterAddress = process.env.DISCOUNT_RATE_ADAPTER_ADDRESS!;
  const termController = process.env.TERM_CONTROLLER_ADDRESS!;
  const discountRateMarkup = process.env.DISCOUNT_RATE_MARKUP!;
  const timeToMaturityThreshold = process.env.TIME_TO_MATURITY_THRESHOLD!;
  const repoTokenConcentrationLimit =
    process.env.REPOTOKEN_CONCENTRATION_LIMIT!;
  const newRequiredReserveRatio = process.env.NEW_REQUIRED_RESERVE_RATIO!;

  await checkUnderlyingVaultAsset(asset, yearnVaultAddress, managedSigner);

  return {
    asset,
    yearnVaultAddress,
    discountRateAdapterAddress,
    eventEmitter,
    deployer,
    termController,
    repoTokenConcentrationLimit,
    timeToMaturityThreshold,
    newRequiredReserveRatio,
    discountRateMarkup,
  };
}

async function deployEventEmitter(managedSigner: Signer) {
  const admin = process.env.ADMIN_ADDRESS!;
  const devops = process.env.DEVOPS_ADDRESS!;

  const EventEmitter = (
    await hre.ethers.getContractFactory("TermVaultEventEmitter")
  ).connect(managedSigner);
  const eventEmitterImpl = await EventEmitter.deploy();
  await eventEmitterImpl.deployed();

  console.log("Deployed event emitter impl to:", eventEmitterImpl.address);

  const Proxy = (await hre.ethers.getContractFactory("ERC1967Proxy")).connect(
    managedSigner
  );
  const initData = EventEmitter.interface.encodeFunctionData("initialize", [
    admin,
    devops,
  ]);

  const eventEmitterProxy = await Proxy.deploy(
    eventEmitterImpl.address,
    initData
  );
  await eventEmitterProxy.deployed();

  console.log("Deployed event emitter proxy to:", eventEmitterProxy.address);

  return hre.ethers.getContractAt(
    "TermVaultEventEmitter",
    await eventEmitterProxy.getAddress(),
    managedSigner
  );
}

async function main() {
  // Get the deployer's address and setup managed signer
  const [deployer] = await hre.ethers.getSigners();
  const managedSigner = new NonceManager(deployer as any) as unknown as Signer;

  // Deploy EventEmitter first
  const eventEmitter = await deployEventEmitter(managedSigner);

  // Build strategy parameters
  const params = await buildStrategyParams(
    await eventEmitter.getAddress(),
    deployer.address,
    managedSigner
  );

  // Deploy Strategy
  const Strategy = (await hre.ethers.getContractFactory("Strategy")).connect(
    managedSigner ?? null
  );
  const strategy = await Strategy.deploy(process.env.STRATEGY_NAME!, params);
  await strategy.deployed();

  console.log("Deployed strategy to:", strategy.address);

  // Post-deployment setup
  const strategyContract = await hre.ethers.getContractAt(
    "ITokenizedStrategy",
    await strategy.getAddress(),
    managedSigner
  );

  await strategyContract.setProfitMaxUnlockTime(
    process.env.PROFIT_MAX_UNLOCK_TIME!
  );
  await strategyContract.setPendingManagement(
    process.env.STRATEGY_MANAGEMENT_ADDRESS!
  );
  await strategyContract.setKeeper(process.env.KEEPER_ADDRESS!);
  await strategyContract.setPerformanceFeeRecipient(process.env.FEE_RECIPIENT!);

  console.log(
    "Set pending management to:",
    process.env.STRATEGY_MANAGEMENT_ADDRESS
  );

  await eventEmitter.pairVaultContract(await strategy.getAddress());
  console.log("Paired strategy with event emitter");

  // Set collateral token parameters
  const collateralTokens = stringToAddressArray(
    process.env.COLLATERAL_TOKEN_ADDRESSES!
  );
  const minCollateralRatios = stringToUintArray(
    process.env.MIN_COLLATERAL_RATIOS!
  );

  if (collateralTokens.length !== minCollateralRatios.length) {
    throw new Error("COLLATERAL_TOKEN_ADDRESSES and MIN_COLLATERAL_RATIOS must have the same number of entries.");
  }
  for (let i = 0; i < collateralTokens.length; i++) {
    await strategy.setCollateralTokenParams(
      collateralTokens[i],
      minCollateralRatios[i]
    );
  }

  await strategy.setPendingGovernor(process.env.GOVERNOR_ROLE_ADDRESS!);
  console.log("Set pending governor to:", process.env.GOVERNOR_ROLE_ADDRESS);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
