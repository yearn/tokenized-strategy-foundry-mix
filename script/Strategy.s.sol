// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import "../src/Strategy.sol";
import "../src/TermVaultEventEmitter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployStrategy is Script {
    /**
     * @dev Converts a comma-separated string of addresses to an array of addresses.
     * @param _input A string containing comma-separated addresses.
     * @return addressArray An array of addresses parsed from the input string.
     */
    function stringToAddressArray(string memory _input) public pure returns (address[] memory) {
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
     * @dev Converts a comma-separated string of integers to a uint256 array.
     * @param _input A string containing comma-separated integers.
     * @return uintArray An array of uint256 parsed from the input string.
     */
    function stringToUintArray(string memory _input) public pure returns (uint256[] memory) {
        // Step 1: Split the input string by commas
        string[] memory parts = splitString(_input, ",");
        
        // Step 2: Convert each part to a uint256
        uint256[] memory uintArray = new uint256[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            uintArray[i] = parseUint(parts[i]);
        }
        
        return uintArray;
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
    /**
     * @dev Helper function to parse a string and convert it to uint256
     * @param _str The string representation of a number
     * @return The uint256 parsed from the input string
     */
    function parseUint(string memory _str) internal pure returns (uint256) {
        bytes memory strBytes = bytes(_str);
        uint256 result = 0;
        
        for (uint256 i = 0; i < strBytes.length; i++) {
            uint8 digit = uint8(strBytes[i]) - 48;
            require(digit >= 0 && digit <= 9, "Invalid character in string");
            result = result * 10 + digit;
        }
        
        return result;
    }

    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        uint256 governorDeployerPK = vm.envUint("GOVERNOR_DEPLOYER_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        string memory name = vm.envString("STRATEGY_NAME");
        address strategyManagement = vm.envAddress("STRATEGY_MANAGEMENT_ADDRESS");
        bool isTest = vm.envBool("IS_TEST");


        TermVaultEventEmitter eventEmitter = _deployEventEmitter();

        Strategy.StrategyParams memory params = buildStrategyParams(address(eventEmitter));

        Strategy strategy = new Strategy(
            name,
            params
        );

        console.log("deployed strategy contract to");
        console.log(address(strategy));

        ITokenizedStrategy(address(strategy)).setPendingManagement(strategyManagement);
        console.log("set pending management");
        console.log(strategyManagement);

        if (isTest) {
            eventEmitter.pairVaultContract(address(strategy));
            console.log("paired strategy contract with event emitter");
        }
        
        vm.stopBroadcast();
    }

    function buildStrategyParams(address eventEmitter) internal returns(Strategy.StrategyParams memory) {
        address asset = vm.envAddress("ASSET_ADDRESS");
        address yearnVaultAddress = vm.envAddress("YEARN_VAULT_ADDRESS");
        address discountRateAdapterAddress = vm.envAddress("DISCOUNT_RATE_ADAPTER_ADDRESS");
        address termController = vm.envAddress("TERM_CONTROLLER_ADDRESS");
        uint256 discountRateMarkup = vm.envUint("DISCOUNT_RATE_MARKUP");
        address governorRoleAddress = vm.envAddress("GOVERNOR_ROLE_ADDRESS");
        uint256 timeToMaturityThreshold = vm.envUint("TIME_TO_MATURITY_THRESHOLD");
        uint256 repoTokenConcentrationLimit = vm.envUint("REPOTOKEN_CONCENTRATION_LIMIT");
        uint256 newRequiredReserveRatio = vm.envUint("NEW_REQUIRED_RESERVE_RATIO");

        checkUnderlyingVaultAsset(asset, yearnVaultAddress);

        Strategy.StrategyParams memory params = Strategy.StrategyParams(
            asset,
            yearnVaultAddress,
            discountRateAdapterAddress,
            address(eventEmitter),
            governorRoleAddress,
            termController,
            repoTokenConcentrationLimit,
            timeToMaturityThreshold,
            newRequiredReserveRatio,
            discountRateMarkup
        );

        return params;

    }

    function checkUnderlyingVaultAsset(address asset, address underlyingVault) internal {
        address underlyingAsset = IERC4626(underlyingVault).asset();
        require(underlyingAsset == asset, "Underlying asset does not match asset");
    }

    function _deployEventEmitter() internal returns(TermVaultEventEmitter eventEmitter) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address devops = vm.envAddress("DEVOPS_ADDRESS");
        TermVaultEventEmitter eventEmitterImpl = new TermVaultEventEmitter();
        console.log("deployed event emitter impl contract to");
        console.log(address(eventEmitterImpl));
        ERC1967Proxy eventEmitterProxy = new ERC1967Proxy(
            address(eventEmitterImpl),
            abi.encodeWithSelector(TermVaultEventEmitter.initialize.selector, admin, devops)
        );
        console.log("deployed event emitter proxy contract to");
        console.log(address(eventEmitterProxy));
        eventEmitter = TermVaultEventEmitter(address(eventEmitterProxy));
    }
}
