// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../src/util/TermFinanceVaultWrappedVotesToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployTermFinanceVaultWrappedVotesToken is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address vaultToken = vm.envAddress("VAULT_TOKEN");
        string memory name = vm.envString("WRAPPED_TOKEN_NAME");
        string memory symbol = vm.envString("WRAPPED_TOKEN_SYMBOL");

        TermFinanceVaultWrappedVotesToken wrappedToken = new TermFinanceVaultWrappedVotesToken(
            ERC20(vaultToken),
            name,
            symbol
        );
        console.log("deployed wrapped token contract to");
        console.log(address(wrappedToken));
        vm.stopBroadcast();
    }
}
