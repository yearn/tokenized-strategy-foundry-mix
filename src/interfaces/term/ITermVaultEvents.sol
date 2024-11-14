// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ITermVaultEvents {
    event VaultContractPaired(address vault);
    
    event TermControllerUpdated(address oldController, address newController);

    event TimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    event RequiredReserveRatioUpdated(uint256 oldThreshold, uint256 newThreshold);

    event DiscountRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup);

    event MinCollateralRatioUpdated(address collateral, uint256 minCollateralRatio);

    event RepoTokenConcentrationLimitUpdated(uint256 oldLimit, uint256 newLimit);
    

    event DepositPaused();

    event DepositUnpaused();

    /*
    event StrategyPaused();

    event StrategyUnpaused();
    */

    event DiscountRateAdapterUpdated(
        address indexed oldAdapter, 
        address indexed newAdapter
    );

    event RepoTokenBlacklistUpdated(
        address indexed repoToken,
        bool blacklisted
    );

    event NewGovernor(address newGovernor);

    function emitTermControllerUpdated(address oldController, address newController) external;

    function emitTimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold) external;

    function emitRequiredReserveRatioUpdated(uint256 oldThreshold, uint256 newThreshold) external;

    function emitDiscountRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup) external;

    function emitMinCollateralRatioUpdated(address collateral, uint256 minCollateralRatio) external;

    function emitRepoTokenConcentrationLimitUpdated(uint256 oldLimit, uint256 newLimit) external;
    

    function emitDepositPaused() external;

    function emitDepositUnpaused() external;
    /*

    function emitStrategyPaused() external;

    function emitStrategyUnpaused() external;*/

    function emitDiscountRateAdapterUpdated(
        address oldAdapter,
        address newAdapter
    ) external;

    function emitRepoTokenBlacklistUpdated(address repoToken, bool blacklisted) external;

    function emitNewGovernor(address newGovernor) external;
}
