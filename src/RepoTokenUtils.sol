// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

library RepoTokenUtils {
    uint256 public constant THREESIXTY_DAYCOUNT_SECONDS = 360 days;
    uint256 public constant RATE_PRECISION = 1e18;

    function repoToPurchasePrecision(
        uint256 repoTokenPrecision, 
        uint256 purchaseTokenPrecision,
        uint256 purchaseTokenAmountInRepoPrecision
    ) internal pure returns (uint256) {
        return (purchaseTokenAmountInRepoPrecision * purchaseTokenPrecision) / repoTokenPrecision;
    }

    function purchaseToRepoPrecision(
        uint256 repoTokenPrecision, 
        uint256 purchaseTokenPrecision,
        uint256 repoTokenAmount
    ) internal pure returns (uint256) {
        return (repoTokenAmount * repoTokenPrecision) / purchaseTokenPrecision;
    }

    function calculatePresentValue(
        uint256 repoTokenAmountInBaseAssetPrecision,
        uint256 purchaseTokenPrecision, 
        uint256 redemptionTimestamp, 
        uint256 auctionRate
    ) internal view returns (uint256 presentValue) {
        uint256 timeLeftToMaturityDayFraction = 
            ((redemptionTimestamp - block.timestamp) * purchaseTokenPrecision) / THREESIXTY_DAYCOUNT_SECONDS;

        // repoTokenAmountInBaseAssetPrecision / (1 + r * days / 360)
        presentValue = 
            (repoTokenAmountInBaseAssetPrecision * purchaseTokenPrecision) / 
            (purchaseTokenPrecision + (auctionRate * timeLeftToMaturityDayFraction / RATE_PRECISION));
    }
}
