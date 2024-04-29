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

    function calculateProceeds(
        uint256 repoTokenAmount,
        uint256 redemptionTimestamp, 
        uint256 repoTokenPrecision, 
        uint256 purchaseTokenPrecision, 
        uint256 auctionRate
    ) internal view returns (uint256) {
        uint256 timeLeftToMaturityDayFraction = 
            ((redemptionTimestamp - block.timestamp) * repoTokenPrecision) / THREESIXTY_DAYCOUNT_SECONDS;

        uint256 purchaseTokenAmountInRepoTokenPrecision = 
            (repoTokenAmount * repoTokenPrecision) / 
            (repoTokenPrecision + (auctionRate * timeLeftToMaturityDayFraction / RATE_PRECISION));

        return repoToPurchasePrecision(
            repoTokenPrecision, purchaseTokenPrecision, purchaseTokenAmountInRepoTokenPrecision
        );
    }
}
