// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./interfaces/term/ITermVaultEvents.sol";
import "@openzeppelin/contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract TermVaultEventEmitter is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ITermVaultEvents
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEVOPS_ROLE = keccak256("DEVOPS_ROLE");
    bytes32 public constant VAULT_CONTRACT = keccak256("VAULT_CONTRACT");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// Initializes the contract
    /// @dev See: https://docs.openzeppelin.com/contracts/4.x/upgradeable
    function initialize(
        address adminWallet_,
        address devopsWallet_
    ) external initializer {
        UUPSUpgradeable.__UUPSUpgradeable_init();
        AccessControlUpgradeable.__AccessControl_init();

        _grantRole(ADMIN_ROLE, adminWallet_);
        _grantRole(DEVOPS_ROLE, devopsWallet_);
    }

    function pairVaultContract(
        address vaultContract
    ) external onlyRole(ADMIN_ROLE) {
        _grantRole(VAULT_CONTRACT, vaultContract);
        emit VaultContractPaired(vaultContract);
    }

    function emitTermControllerUpdated(
        address oldController,
        address newController
    ) external onlyRole(VAULT_CONTRACT) {
        emit TermControllerUpdated(oldController, newController);
    }

    function emitTimeToMaturityThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    ) external onlyRole(VAULT_CONTRACT) {
        emit TimeToMaturityThresholdUpdated(oldThreshold, newThreshold);
    }

    function emitRequiredReserveRatioUpdated(
        uint256 oldThreshold,
        uint256 newThreshold
    ) external onlyRole(VAULT_CONTRACT) {
        emit RequiredReserveRatioUpdated(oldThreshold, newThreshold);
    }

    function emitDiscountRateMarkupUpdated(
        uint256 oldMarkup,
        uint256 newMarkup
    ) external onlyRole(VAULT_CONTRACT) {
        emit DiscountRateMarkupUpdated(oldMarkup, newMarkup);
    }

    function emitMinCollateralRatioUpdated(
        address collateral,
        uint256 minCollateralRatio
    ) external onlyRole(VAULT_CONTRACT) {
        emit MinCollateralRatioUpdated(collateral, minCollateralRatio);
    }

    function emitRepoTokenConcentrationLimitUpdated(
        uint256 oldLimit,
        uint256 newLimit
    ) external onlyRole(VAULT_CONTRACT) {
        emit RepoTokenConcentrationLimitUpdated(oldLimit, newLimit);
    }

    function emitDepositPaused() external onlyRole(VAULT_CONTRACT) {
        emit DepositPaused();
    }

    function emitDepositUnpaused() external onlyRole(VAULT_CONTRACT) {
        emit DepositUnpaused();
    }
    /*
    function emitStrategyPaused() external onlyRole(VAULT_CONTRACT) {
        emit StrategyPaused();
    }

    function emitStrategyUnpaused() external onlyRole(VAULT_CONTRACT) {
        emit StrategyUnpaused();
    }*/

    function emitDiscountRateAdapterUpdated(
        address oldAdapter,
        address newAdapter
    ) external onlyRole(VAULT_CONTRACT) {
        emit DiscountRateAdapterUpdated(oldAdapter, newAdapter);
    }

    function emitRepoTokenBlacklistUpdated(
        address repoToken,
        bool blacklisted
    ) external onlyRole(VAULT_CONTRACT) {
        emit RepoTokenBlacklistUpdated(repoToken, blacklisted);
    }

    function emitNewGovernor(
        address newGovernor
    ) external onlyRole(VAULT_CONTRACT) {
        emit NewGovernor(newGovernor);
    }

    // ========================================================================
    // = Admin  ===============================================================
    // ========================================================================

    // solhint-disable no-empty-blocks
    ///@dev required override by the OpenZeppelin UUPS module
    function _authorizeUpgrade(
        address
    ) internal view override onlyRole(DEVOPS_ROLE) {}
    // solhint-enable no-empty-blocks
}
