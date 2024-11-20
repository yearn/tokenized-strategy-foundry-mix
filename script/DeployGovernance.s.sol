// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "forge-std/Script.sol";
import "../src/Strategy.sol";

interface TermVaultGovernanceFactory {
    function deploySafe(
        address proposer,
        address strategy,
        address governor,
        address[] calldata vaultGovernors
    ) external;
}

contract DeployGovernance is Script {
     /**
     * @dev Converts a comma-separated string of addresses to an array of addresses.
     * @param _input A string containing comma-separated addresses.
     * @return addressArray An array of addresses parsed from the input string.
     */
    function stringToAddressArray(string memory _input) public pure returns (address[] memory) {
        if (_input == "") {
            return new address[](0);
        }
        // Step 1: Split the input string by commas
        string[] memory parts = splitString(_input, ",");
        
        // Step 2: Convert each part to an address
        address[] memory addressArray = new address[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            addressArray[i] = parseAddress(parts[i]);
        }
        
        return addressArray;
    }


    /**
     * @dev Helper function to split a string by a delimiter
     * @param _str The input string
     * @param _delimiter The delimiter to split by
     * @return An array of substrings
     */
    function splitString(string memory _str, string memory _delimiter) internal pure returns (string[] memory) {
        bytes memory strBytes = bytes(_str);
        bytes memory delimiterBytes = bytes(_delimiter);
        uint256 partsCount = 1;
        
        // Count the parts to split the string
        for (uint256 i = 0; i < strBytes.length - 1; i++) {
            if (strBytes[i] == delimiterBytes[0]) {
                partsCount++;
            }
        }
        
        string[] memory parts = new string[](partsCount);
        uint256 partIndex = 0;
        bytes memory part;
        
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimiterBytes[0]) {
                parts[partIndex] = string(part);
                part = "";
                partIndex++;
            } else {
                part = abi.encodePacked(part, strBytes[i]);
            }
        }
        
        // Add the last part
        parts[partIndex] = string(part);
        
        return parts;
    }
    
    /**
     * @dev Helper function to parse a string and convert it to an address
     * @param _str The string representation of an address
     * @return The address parsed from the input string
     */
    function parseAddress(string memory _str) internal pure returns (address) {
        bytes memory tmp = bytes(_str);
        require(tmp.length == 42, "Invalid address length"); // Must be 42 characters long (0x + 40 hex chars)
        
        uint160 addr = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint160 b = uint160(uint8(tmp[i]));

            if (b >= 48 && b <= 57) { // 0-9
                addr = addr * 16 + (b - 48);
            } else if (b >= 65 && b <= 70) { // A-F
                addr = addr * 16 + (b - 55);
            } else if (b >= 97 && b <= 102) { // a-f
                addr = addr * 16 + (b - 87);
            } else {
                revert("Invalid address character");
            }
        }
        
        return address(addr);
    }

    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        TermVaultGovernanceFactory factory = TermVaultGovernanceFactory(vm.envAddress("GOVERNANCE_FACTORY"));
        address proposer = vm.envAddress("PROPOSER");
        address strategy = vm.envAddress("STRATEGY");
        address governor = vm.envAddress("GOVERNOR");
        address[] memory vaultGovernors = stringToAddressArray(vm.envString("VAULT_GOVERNORS"));

        factory.deploySafe(proposer, strategy, governor, vaultGovernors);

        vm.stopBroadcast();
    }

}