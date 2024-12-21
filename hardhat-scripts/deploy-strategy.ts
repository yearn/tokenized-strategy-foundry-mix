import { ethers } from "hardhat";  // Use direct ethers import
import "@nomiclabs/hardhat-ethers";
import { NonceManager } from "@ethersproject/experimental";
import dotenv from "dotenv";
import { Signer } from "ethers";
import { promises as fs } from 'fs';
import path from 'path';


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
    await ethers.getContractFactory("TermVaultEventEmitter")
  ).connect(managedSigner);
  const eventEmitterImpl = await EventEmitter.deploy();
  await eventEmitterImpl.deployed();

  console.log("Deployed event emitter impl to:", eventEmitterImpl.address);

  const Proxy = (await ethers.getContractFactory("ERC1967Proxy")).connect(
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

  return ethers.getContractAt(
    "TermVaultEventEmitter",
    eventEmitterProxy.address,
    managedSigner
  );
}

async function main() {
  // Try both Foundry and Hardhat artifact locations
const possibleArtifactPaths = [
  path.join(process.cwd(), 'out/Strategy.sol/Strategy.json'),
  path.join(process.cwd(), 'artifacts/src/Strategy.sol/Strategy.json')
];

// Check each path
for (const artifactPath of possibleArtifactPaths) {
  console.log(`Checking ${artifactPath}`);
  try {
    const exists = await fs.access(artifactPath).then(() => true).catch(() => false);
    if (exists) {
      console.log(`Found artifact at: ${artifactPath}`);
      const artifact = JSON.parse(await fs.readFile(artifactPath, 'utf8'));
      console.log(`Artifact contains: `, Object.keys(artifact));
    }
  } catch (e) {
    console.log(`Error with ${artifactPath}:`, e);
  }
}

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
  console.log(await managedSigner.getAddress())

  // Match your working pattern exactly
  const Strategy = await ethers.getContractFactory(
    "Strategy",
    {
      signer: managedSigner,
    }
  );

  const connectedStrategy = Strategy.connect(
    managedSigner
  );
  // Log the deployment attempt
  console.log("Strategy factory created with:", {
    hasAbi: !!connectedStrategy.interface,
    hasBytecode: !!connectedStrategy.bytecode,
    signer: await managedSigner.getAddress()
  });

  console.log("Constructor ABI:", Strategy.interface.deploy);




  const strategyMeta = process.env.STRATEGY_META!;
  const [strategyName, strategySymbol] = strategyMeta.trim().split(",").map(x => x.trim())
  console.log(`Deploying strategy with (${strategyName}, ${strategySymbol})`);
    // Log the exact values we're passing
  console.log("Deploying with:", {
    strategyName,
    strategySymbol,
    params: {
        ...params,
        // Convert BigNumber values to strings for logging
        repoTokenConcentrationLimit: params.repoTokenConcentrationLimit.toString(),
        timeToMaturityThreshold: params.timeToMaturityThreshold.toString(),
        newRequiredReserveRatio: params.newRequiredReserveRatio.toString(),
        discountRateMarkup: params.discountRateMarkup.toString()
    }
  });
  console.log("About to deploy with params:", {
    funcFragment: Strategy.interface.deploy,
    args: [strategyName, strategySymbol, params]
  });
  
  const deployTx = await Strategy.getDeployTransaction(
    strategyName,
    strategySymbol,
    params
  );
  console.log("Deploy transaction:", {
    from: deployTx.from,
    data: deployTx.data?.toString().substring(0, 100) + '...' // Just first 100 chars
  });
  
  // Create a struct that exactly matches the constructor's tuple type
  const strategy = await Strategy.deploy(
    strategyName,
    strategySymbol,
    params
  );

  await strategy.deployed();
  

  console.log(JSON.stringify(strategy));
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
  await strategyContract.setPendingManagement(
    process.env.STRATEGY_MANAGEMENT_ADDRESS!
  );
  await strategyContract.setKeeper(process.env.KEEPER_ADDRESS!);
  await strategyContract.setPerformanceFeeRecipient(process.env.FEE_RECIPIENT!);

  console.log(
    "Set pending management to:",
    process.env.STRATEGY_MANAGEMENT_ADDRESS
  );

  await eventEmitter.pairVaultContract(strategy.address);
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
