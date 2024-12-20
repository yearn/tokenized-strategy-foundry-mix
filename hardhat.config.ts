import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-ethers";
import { task } from "hardhat/config";
import path from "path";
import glob from "glob";

task("compile", "Compiles the project, excluding specific files", async (_, { run }) => {
  const excludedPaths = [
    path.resolve(__dirname, "src/test/kontrol/*.sol"),
  ];

  const allFiles = glob.sync(path.resolve(__dirname, "src/*.sol"));
  const filesToCompile = allFiles.filter(
    (file) => !excludedPaths.some((excluded) => file.startsWith(excluded))
  );

  console.log("Files to compile:", filesToCompile);

  await run("compile:solidity", { sources: filesToCompile, force: false, quiet: false });
});

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./src", // Specify the main directory for source files
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155111
    },
    avalanche: {
      url: process.env.AVALANCHE_RPC_URL || "https://api.avax.network/ext/bc/C/rpc",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 43114
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 1
    }
  }
};

export default config;