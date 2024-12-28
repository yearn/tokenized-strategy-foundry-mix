// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

interface IStrategy {
    function report() external;
}

interface IVault {
    function process_report(address strategy) external;
    function updateDebt(address strategy, uint256 targetAmount) external;
}

contract TermVaultsKeeper is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address devops, address initialKeeper) public initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, devops);
        _setupRole(KEEPER_ROLE, initialKeeper);
    }

    function reports(address[] calldata strategies, address vault, address[] calldata vaultStrategies) external onlyRole(KEEPER_ROLE) {
        _callStrategyReports(strategies);
        _processReports(vault, vaultStrategies);
    }

    function _callStrategyReports(address[] calldata strategies) internal  {
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy(strategies[i]).report();
        }
    }

    function _processReports(address vault, address[] calldata strategies) internal {
        for (uint256 i = 0; i < strategies.length; i++) {
            IVault(vault).process_report(strategies[i]);
        }
    }

    function rebalanceVault(address vault, address[] calldata withdrawStrategies, uint256[] calldata withdrawTargetAmounts, address[] calldata depositStrategies, uint256[] calldata depositTargetAmounts) external onlyRole(KEEPER_ROLE) {
        _withdraw(vault, withdrawStrategies, withdrawTargetAmounts);
        _deposit(vault, depositStrategies, depositTargetAmounts);
    }

    function _withdraw(address vault, address[] calldata withdrawStrategies, uint256[] calldata withdrawTargetAmounts) internal {
        for (uint256 i = 0; i < withdrawStrategies.length; i++) {
            IVault(vault).updateDebt(withdrawStrategies[i], withdrawTargetAmounts[i]);
        }
    }

    function _deposit(address vault, address[] calldata depositStrategies, uint256[] calldata despositTargetAmounts) internal {
        for (uint256 i = 0; i < depositStrategies.length - 1; i++) {
            IVault(vault).updateDebt(depositStrategies[i], despositTargetAmounts[i]);
        }
        IVault(vault).updateDebt(depositStrategies[depositStrategies.length - 1], type(uint256).max);   
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}