// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ITermVaultEvents {
    event TermControllerUpdated(address oldController, address newController);

    event TimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    event LiquidityReserveRatioUpdated(uint256 oldThreshold, uint256 newThreshold);

    event AuctionRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup);

    event MinCollateralRatioUpdated(address collateral, uint256 minCollateralRatio);

    event RepoTokenConcentrationLimitUpdated(uint256 oldLimit, uint256 newLimit);

    event Paused();

    event Unpaused();

    event DiscountRateAdapterUpdated(
        address indexed oldAdapter, 
        address indexed newAdapter
    );

    function emitTermControllerUpdated(address oldController, address newController) external;

    function emitTimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold) external;

    function emitLiquidityReserveRatioUpdated(uint256 oldThreshold, uint256 newThreshold) external;

    function emitDiscountRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup) external;

    function emitMinCollateralRatioUpdated(address collateral, uint256 minCollateralRatio) external;

    function emitRepoTokenConcentrationLimitUpdated(uint256 oldLimit, uint256 newLimit) external;

    function emitPaused() external;

    function emitUnpaused() external;

    function emitDiscountRateAdapterUpdated(
        address oldAdapter,
        address newAdapter
    ) external;
}
