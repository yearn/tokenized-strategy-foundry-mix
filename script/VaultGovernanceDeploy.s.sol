// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "forge-std/Script.sol";

interface TermVaultGovernanceFactory {
    function deploySafe(
        address proposer,
        address vault,
        address accountant,
        address governor
    ) external;
}

contract VaultGovernanceDeploy is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        TermVaultGovernanceFactory factory = TermVaultGovernanceFactory(vm.envAddress("GOVERNANCE_FACTORY"));
        address proposer = vm.envAddress("PROPOSER");
        address vault = vm.envAddress("VAULT");
        address accountant = vm.envAddress("ACCOUNTANT");
        address governor = vm.envAddress("GOVERNOR");

        factory.deploySafe(proposer, vault, accountant, governor);

        vm.stopBroadcast();
    }

}