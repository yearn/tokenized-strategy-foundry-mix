// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../src/Strategy.sol";
import "../src/TermVaultEventEmitter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployStrategy is Script {
    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        // Retrieve environment variables
        address asset = vm.envAddress("ASSET_ADDRESS");
        string memory name = vm.envString("STRATEGY_NAME");
        address yearnVaultAddress = vm.envAddress("YEARN_VAULT_ADDRESS");
        address discountRateAdapterAddress = vm.envAddress("DISCOUNT_RATE_ADAPTER_ADDRESS");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address devops = vm.envAddress("DEVOPS_ADDRESS");
        address strategyManagement = vm.envAddress("STRATEGY_MANAGEMENT_ADDRESS");
        address governorRoleAddress = vm.envAddress("GOVERNOR_ROLE_ADDRESS");
        address termController = vm.envOr("TERM_CONTROLLER_ADDRESS", address(0));
        uint256 discountRateMarkup = vm.envOr("DISCOUNT_RATE_MARKUP", uint256(0));
        address collateralTokenAddr = vm.envOr("COLLATERAL_TOKEN_ADDR", address(0));
        uint256 minCollateralRatio = vm.envOr("MIN_COLLATERAL_RATIO", uint256(0));
        uint256 timeToMaturityThreshold = vm.envOr("TIME_TO_MATURITY_THRESHOLD", uint256(0));
        uint256 repoTokenConcentrationLimit = vm.envOr("REPOTOKEN_CONCENTRATION_LIMIT", uint256(0));
        bool isTest = vm.envBool("IS_TEST");

        TermVaultEventEmitter eventEmitter = _deployEventEmitter(admin, devops);

        Strategy strategy = new Strategy(asset,
            name,
            yearnVaultAddress,
            discountRateAdapterAddress,
            address(eventEmitter),
            governorRoleAddress
        );

        console.log("deployed strategy contract to");
        console.log(address(strategy));

        if (isTest) {
            eventEmitter.pairVaultContract(address(strategy));
            console.log("paired strategy contract with event emitter");

            strategy.setTermController(termController);
            console.log("set term controller");
            console.log(termController);

            strategy.setDiscountRateMarkup(discountRateMarkup);
            console.log("set discount rate markup");
            console.log(discountRateMarkup);

            strategy.setCollateralTokenParams(collateralTokenAddr, minCollateralRatio);
            console.log("set collateral token params");
            console.log(collateralTokenAddr);
            console.log(minCollateralRatio);

            strategy.setTimeToMaturityThreshold(timeToMaturityThreshold);
            console.log("set time to maturity threshold");
            console.log(timeToMaturityThreshold);

            strategy.setRepoTokenConcentrationLimit(repoTokenConcentrationLimit);
            console.log("set repo token concentration limit");
            console.log(repoTokenConcentrationLimit);

            strategy.setPendingManagement(strategyManagement);
            console.log("set pending management");
            strategy.acceptManagement();
        }
        
        vm.stopBroadcast();
    }

    function _deployEventEmitter(address admin, address devops) internal returns(TermVaultEventEmitter eventEmitter) {
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
