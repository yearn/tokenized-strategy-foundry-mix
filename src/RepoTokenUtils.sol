// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";

/*//////////////////////////////////////////////////////////////
                        LIBRARY: RepoTokenUtils
//////////////////////////////////////////////////////////////*/

library RepoTokenUtils {
    uint256 public constant THREESIXTY_DAYCOUNT_SECONDS = 360 days;
    uint256 public constant RATE_PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the present value of a repoToken
     * @param repoTokenAmountInBaseAssetPrecision The amount of repoToken in base asset precision
     * @param purchaseTokenPrecision The precision of the purchase token
     * @param redemptionTimestamp The redemption timestamp of the repoToken
     * @param discountRate The auction rate
     * @return presentValue The present value of the repoToken
     */
    function calculatePresentValue(
        uint256 repoTokenAmountInBaseAssetPrecision,
        uint256 purchaseTokenPrecision, 
        uint256 redemptionTimestamp, 
        uint256 discountRate
    ) internal view returns (uint256 presentValue) {
        uint256 timeLeftToMaturityDayFraction = block.timestamp > redemptionTimestamp ? 0 : 
            ((redemptionTimestamp - block.timestamp) * purchaseTokenPrecision) / THREESIXTY_DAYCOUNT_SECONDS;

        // repoTokenAmountInBaseAssetPrecision / (1 + r * days / 360)
        presentValue = 
            (repoTokenAmountInBaseAssetPrecision * purchaseTokenPrecision) / 
            (purchaseTokenPrecision + (discountRate * timeLeftToMaturityDayFraction / RATE_PRECISION));

        return presentValue > repoTokenAmountInBaseAssetPrecision ? repoTokenAmountInBaseAssetPrecision : presentValue;
    }

    /**
     * @notice Get the normalized amount of a repoToken in base asset precision
     * @param repoToken The address of the repoToken
     * @param repoTokenAmount The amount of the repoToken
     * @param purchaseTokenPrecision The precision of the purchase token
     * @param repoRedemptionHaircut The haircut to be applied to the repoToken for bad debt
     * @return repoTokenAmountInBaseAssetPrecision The normalized amount of the repoToken in base asset precision
     */
    function getNormalizedRepoTokenAmount(
        address repoToken, 
        uint256 repoTokenAmount, 
        uint256 purchaseTokenPrecision,
        uint256 repoRedemptionHaircut
    ) internal view returns (uint256 repoTokenAmountInBaseAssetPrecision) {
        uint256 repoTokenPrecision = 10**ERC20(repoToken).decimals();
        uint256 redemptionValue = ITermRepoToken(repoToken).redemptionValue();
        repoTokenAmountInBaseAssetPrecision =
            repoRedemptionHaircut != 0 ?
            (redemptionValue * repoRedemptionHaircut * repoTokenAmount * purchaseTokenPrecision) / 
            (repoTokenPrecision * RATE_PRECISION * 1e18)
            : (redemptionValue * repoTokenAmount * purchaseTokenPrecision) / (repoTokenPrecision * RATE_PRECISION);
    }
}