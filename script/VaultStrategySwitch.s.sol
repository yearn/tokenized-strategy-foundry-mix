// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "@yearn-vaults/interfaces/IVault.sol";
import "@yearn-vaults/interfaces/IVaultFactory.sol";
import "vault-periphery/contracts/accountants/Accountant.sol";
import "vault-periphery/contracts/accountants/AccountantFactory.sol";

contract VaultStrategySwitch is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address yearnVaultAddress = vm.envAddress("YEARN_VAULT_ADDRESS");
        address newStrategy = vm.envAddress("NEW_STRATEGY_ADDRESS");
        address[] memory strategiesDefaultQueue = stringToAddresses(vm.envString("STRATEGIES_DEFAULT_QUEUE"), ",");
        address oldStrategy = vm.envOr("OLD_STRATEGY_ADDRESS", address(0));
        

        IVault vault = IVault(yearnVaultAddress);
        vault.add_strategy(newStrategy);
        console.log("added strategy to vault");
        console.log(newStrategy);
        vault.set_default_queue(strategiesDefaultQueue);
        console.log("set default queue for vault");


        if (oldStrategy != address(0)) {
            try vault.update_debt(oldStrategy, 0){
                console.log("updated debt for old strategy to 0");

            } catch (bytes memory lowLevelData) {

            }
            console.log(oldStrategy);

            vault.revoke_strategy(oldStrategy);
            console.log("revoked strategy from vault");
            console.log(oldStrategy);

            vault.set_default_queue(strategiesDefaultQueue);
            console.log("set default queue for vault");
        }        
        vm.stopBroadcast();
    }

     function stringToAddresses(string memory _str, string memory _delimiter) internal pure returns (address[] memory) {
        // Split the string
        string[] memory parts = split(_str, _delimiter);
        
        // Convert each part to an address
        address[] memory addresses = new address[](parts.length);
        for (uint i = 0; i < parts.length; i++) {
            addresses[i] = vm.parseAddress(parts[i]);
        }
        
        return addresses;
    }

    function split(string memory _base, string memory _delimiter) internal pure returns (string[] memory) {
        bytes memory baseBytes = bytes(_base);
        bytes memory delBytes = bytes(_delimiter);

        uint count = 1;
        for (uint i = 0; i < baseBytes.length; i++) {
            if (keccak256(abi.encodePacked(baseBytes[i])) == keccak256(abi.encodePacked(delBytes[0]))) {
                count++;
            }
        }

        string[] memory parts = new string[](count);

        count = 0;
        uint lastIndex = 0;
        for (uint i = 0; i < baseBytes.length; i++) {
            if (keccak256(abi.encodePacked(baseBytes[i])) == keccak256(abi.encodePacked(delBytes[0]))) {
                parts[count] = substring(_base, lastIndex, i);
                lastIndex = i + 1;
                count++;
            }
        }
        parts[count] = substring(_base, lastIndex, baseBytes.length);

        return parts;
    }

    function substring(string memory _base, uint _start, uint _end) internal pure returns (string memory) {
        bytes memory baseBytes = bytes(_base);
        require(_start <= _end && _end <= baseBytes.length, "Invalid substring range");

        bytes memory result = new bytes(_end - _start);
        for (uint i = _start; i < _end; i++) {
            result[i - _start] = baseBytes[i];
        }

        return string(result);
    }
}
