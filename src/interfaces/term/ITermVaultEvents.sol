// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ITermVaultEvents {
    event TermControllerUpdated(address oldController, address newController);

    event TimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    event LiquidityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    event AuctionRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup);

    function emitTermControllerUpdated(address oldController, address newController) external;

    function emitTimeToMaturityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold) external;

    function emitLiquidityThresholdUpdated(uint256 oldThreshold, uint256 newThreshold) external;

    function emitAuctionRateMarkupUpdated(uint256 oldMarkup, uint256 newMarkup) external;
}
