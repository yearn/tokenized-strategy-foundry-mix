// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./interfaces/term/ITermVaultEvents.sol";
import "@openzeppelin/contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract TermListingEventEmitter is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ITermVaultEvents {

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
    )
    external initializer {
        UUPSUpgradeable.__UUPSUpgradeable_init();
        AccessControlUpgradeable.__AccessControl_init();

        _grantRole(ADMIN_ROLE, adminWallet_);
        _grantRole(DEVOPS_ROLE, devopsWallet_);
    }

    function pairVaultContract(address vaultContract) external onlyRole(ADMIN_ROLE){
        _grantRole(VAULT_CONTRACT, vaultContract);
    }

    function emitTermControllerUpdated(address oldController, address newController) external {
        emit TermControllerUpdated(oldController, newController);
    }

    function emitTimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold) external {
        emit TimeToMaturityThresholdUpdated(oldThreshold, newThreshold);
    }

    function emitLiquidityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold) external {
        emit LiquidityThresholdUpdated(oldThreshold, newThreshold);
    }

    function emitAuctionRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup) external {
        emit AuctionRateMarkupUpdated(oldMarkup, newMarkup);
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