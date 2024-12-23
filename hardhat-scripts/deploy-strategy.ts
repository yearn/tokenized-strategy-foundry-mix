import { ethers } from "hardhat";  // Use direct ethers import
import "@nomiclabs/hardhat-ethers";
import { NonceManager } from "@ethersproject/experimental";
import dotenv from "dotenv";
import { Signer } from "ethers";
import { promises as fs } from 'fs';
import path from 'path';
import { Strategy } from '../typechain-types/src/Strategy';
type StrategyParamsStruct = Strategy.StrategyParamsStruct;


dotenv.config();

function stringToAddressArray(input: string): string[] {
  if (!input) return [];
  return input.split(",").map((addr) => {
    const trimmed = addr.trim();
    if (!ethers.utils.isAddress(trimmed)) {
      throw new Error(`Invalid address: ${trimmed}`);
    }
    return trimmed;
  });
}

function stringToUintArray(input: string): string[] {  // Changed return type to string[]
  if (!input) return [];
  return input.split(",").map((num) => {
    const trimmed = num.trim();
    // Just validate that it's a valid number string but return the string
    if (isNaN(Number(trimmed))) {
      throw new Error(`Invalid number: ${trimmed}`);
    }
    return trimmed;  // Return the string instead of parsing to number
  });
}

async function checkUnderlyingVaultAsset(
  asset: string,
  underlyingVault: string,
  managedSigner: Signer
) {
  const vault = await ethers.getContractAt(
    "IERC4626",
    underlyingVault,
    managedSigner
  );
  const underlyingAsset = await vault.asset();
  if (underlyingAsset.toLowerCase() !== asset.toLowerCase()) {
    throw new Error(`Underlying asset (${underlyingAsset}) does not match asset (${asset})`);
  }
}

async function buildStrategyParams(
  _eventEmitter: string,
  deployer: string,
  managedSigner: Signer
) {
  const _asset = process.env.ASSET_ADDRESS!;
  const _yearnVault = process.env.YEARN_VAULT_ADDRESS!;
  const _discountRateAdapter = process.env.DISCOUNT_RATE_ADAPTER_ADDRESS!;
  const _termController = process.env.TERM_CONTROLLER_ADDRESS!;
  const _discountRateMarkup = process.env.DISCOUNT_RATE_MARKUP!;
  const _timeToMaturityThreshold = process.env.TIME_TO_MATURITY_THRESHOLD!;
  const _repoTokenConcentrationLimit = process.env.REPOTOKEN_CONCENTRATION_LIMIT!;
  const _requiredReserveRatio = process.env.NEW_REQUIRED_RESERVE_RATIO!;

  await checkUnderlyingVaultAsset(_asset, _yearnVault, managedSigner);

  return {
    _asset,
    _yearnVault,
    _discountRateAdapter,
    _eventEmitter,
    _governorAddress: deployer,
    _termController,
    _repoTokenConcentrationLimit,
    _timeToMaturityThreshold,
    _requiredReserveRatio,
    _discountRateMarkup,
  } as StrategyParamsStruct;
}

async function deployEventEmitter(managedSigner: Signer) {
  const admin = process.env.ADMIN_ADDRESS!;
  const devops = process.env.DEVOPS_ADDRESS!;
  let eventEmitterImpl = process.env.EVENT_EMITTER_ADDRESS;

  const EventEmitter = (
    await ethers.getContractFactory("TermVaultEventEmitter")
  ).connect(managedSigner);
  if (!eventEmitterImpl) {
    const eventEmitterImplContract = await EventEmitter.deploy();
    await eventEmitterImplContract.deployed();
    console.log("Deployed event emitter impl to:", eventEmitterImplContract.address);
    eventEmitterImpl = eventEmitterImplContract.address;
  }
  
  const Proxy = (await ethers.getContractFactory("ERC1967Proxy")).connect(
    managedSigner
  );
  const initData = EventEmitter.interface.encodeFunctionData("initialize", [
    admin,
    devops,
  ]);

  const eventEmitterProxy = await Proxy.deploy(
    eventEmitterImpl,
    initData
  );
  await eventEmitterProxy.deployed();
  console.log("Using event emitter impl at:", eventEmitterImpl);

  console.log("Deployed event emitter proxy to:", eventEmitterProxy.address);

  return ethers.getContractAt(
    "TermVaultEventEmitter",
    eventEmitterProxy.address,
    managedSigner
  );
}

async function main() {
  // Get the deployer's address and setup managed signer
  const [deployer] = await ethers.getSigners();
  const managedSigner = new NonceManager(deployer as any) as unknown as Signer;

  // Deploy EventEmitter first
  const eventEmitter = await deployEventEmitter(managedSigner);

  // Build strategy parameters
  const params = await buildStrategyParams(
    eventEmitter.address,
    deployer.address,
    managedSigner
  );
  console.log(JSON.stringify(params));

  // Match your working pattern exactly
  const Strategy = await ethers.getContractFactory(
    "Strategy",
    {
      signer: managedSigner,
    }
  );

  const strategyMeta = process.env.STRATEGY_META!;
  const [strategyName, strategySymbol] = strategyMeta.trim().split(",").map(x => x.trim())
  console.log(`Deploying strategy with (${strategyName}, ${strategySymbol})`);

  
  // Create a struct that exactly matches the constructor's tuple type
  const strategy = await Strategy.deploy(
    strategyName,
    strategySymbol,
    params
  );

  await strategy.deployed();
  
  console.log("Deployed strategy to:", strategy.address);

  // Post-deployment setup
  const strategyContract = await ethers.getContractAt(
    "ITokenizedStrategy",
    strategy.address,
    managedSigner
  );

  await strategyContract.setProfitMaxUnlockTime(
    process.env.PROFIT_MAX_UNLOCK_TIME!
  );
  const tx1 = await strategyContract.setProfitMaxUnlockTime(
    process.env.PROFIT_MAX_UNLOCK_TIME!
  );
  await tx1.wait();
  console.log("Set profit max unlock time to:", process.env.PROFIT_MAX_UNLOCK_TIME, "Transaction hash:", tx1.hash);

  const tx2 = await strategyContract.setPendingManagement(
    process.env.STRATEGY_MANAGEMENT_ADDRESS!
  );
  await tx2.wait();
  console.log("Set pending management to:", process.env.STRATEGY_MANAGEMENT_ADDRESS, "Transaction hash:", tx2.hash);

  const tx3 = await strategyContract.setKeeper(process.env.KEEPER_ADDRESS!);
  await tx3.wait();
  console.log("Set keeper to:", process.env.KEEPER_ADDRESS, "Transaction hash:", tx3.hash);

  const tx4 = await strategyContract.setPerformanceFeeRecipient(process.env.FEE_RECIPIENT!);
  await tx4.wait();
  console.log("Set performance fee recipient to:", process.env.FEE_RECIPIENT, "Transaction hash:", tx4.hash);

  const tx5 = await eventEmitter.pairVaultContract(strategy.address);
  await tx5.wait();
  console.log("Paired strategy with event emitter. Transaction hash:", tx5.hash);

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
