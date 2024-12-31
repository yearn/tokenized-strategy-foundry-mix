// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermController} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";
import {ITermRepoCollateralManager} from "./interfaces/term/ITermRepoCollateralManager.sol";
import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";

struct RepoTokenListNode {
    address next;
}

struct RepoTokenListData {
    address head;
    mapping(address => RepoTokenListNode) nodes;
    mapping(address => uint256) discountRates;
    /// @notice keyed by collateral token
    mapping(address => uint256) collateralTokenParams;
}

/*//////////////////////////////////////////////////////////////
                        LIBRARY: RepoTokenList
//////////////////////////////////////////////////////////////*/

library RepoTokenList {
    address internal constant NULL_NODE = address(0);
    uint256 internal constant INVALID_AUCTION_RATE = 0;
    uint256 internal constant ZERO_AUCTION_RATE = 1; //Set to lowest nonzero number so that it is not confused with INVALID_AUCTION_RATe but still calculates as if 0.

    error InvalidRepoToken(address token);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the redemption (maturity) timestamp of a repoToken
     * @param repoToken The address of the repoToken
     * @return redemptionTimestamp The timestamp indicating when the repoToken matures
     *
     * @dev This function calls the `config()` method on the repoToken to retrieve its configuration details,
     * including the redemption timestamp, which it then returns.
     */
    function getRepoTokenMaturity(
        address repoToken
    ) internal view returns (uint256 redemptionTimestamp) {
        (redemptionTimestamp, , , ) = ITermRepoToken(repoToken).config();
    }

    /**
     * @notice Get the next node in the list
     * @param listData The list data
     * @param current The current node
     * @return The next node
     */
    function _getNext(
        RepoTokenListData storage listData,
        address current
    ) private view returns (address) {
        return listData.nodes[current].next;
    }

    /**
     * @notice Count the number of nodes in the list
     * @param listData The list data
     * @return count The number of nodes in the list
     */
    function _count(
        RepoTokenListData storage listData
    ) private view returns (uint256 count) {
        if (listData.head == NULL_NODE) return 0;
        address current = listData.head;
        while (current != NULL_NODE) {
            count++;
            current = _getNext(listData, current);
        }
    }

    /**
     * @notice Returns an array of addresses representing the repoTokens currently held in the list data
     * @param listData The list data
     * @return holdingsArray An array of addresses of the repoTokens held in the list
     *
     * @dev This function iterates through the list of repoTokens and returns their addresses in an array.
     * It first counts the number of repoTokens, initializes an array of that size, and then populates the array
     * with the addresses of the repoTokens.
     */
    function holdings(
        RepoTokenListData storage listData
    ) internal view returns (address[] memory holdingsArray) {
        uint256 count = _count(listData);
        if (count > 0) {
            holdingsArray = new address[](count);
            uint256 i;
            address current = listData.head;
            while (current != NULL_NODE) {
                holdingsArray[i++] = current;
                current = _getNext(listData, current);
            }
        }
    }

    /**
     * @notice Get the weighted time to maturity of the strategy's holdings of a specified repoToken
     * @param repoToken The address of the repoToken
     * @param repoTokenBalanceInBaseAssetPrecision The balance of the repoToken in base asset precision
     * @return weightedTimeToMaturity The weighted time to maturity in seconds x repoToken balance in base asset precision
     */
    function getRepoTokenWeightedTimeToMaturity(
        address repoToken,
        uint256 repoTokenBalanceInBaseAssetPrecision
    ) internal view returns (uint256 weightedTimeToMaturity) {
        uint256 currentMaturity = getRepoTokenMaturity(repoToken);

        if (currentMaturity > block.timestamp) {
            uint256 timeToMaturity = _getRepoTokenTimeToMaturity(
                currentMaturity
            );
            // Not matured yet
            weightedTimeToMaturity =
                timeToMaturity *
                repoTokenBalanceInBaseAssetPrecision;
        }
    }

    /**
     * @notice This function calculates the cumulative weighted time to maturity and cumulative amount of all repoTokens in the list.
     * @param listData The list data
     * @param discountRateAdapter The discount rate adapter
     * @param repoToken The address of the repoToken (optional)
     * @param repoTokenAmount The amount of the repoToken (optional)
     * @param purchaseTokenPrecision The precision of the purchase token
     * @return cumulativeWeightedTimeToMaturity The cumulative weighted time to maturity for all repoTokens
     * @return cumulativeRepoTokenAmount The cumulative repoToken amount across all repoTokens
     * @return found Whether the specified repoToken was found in the list
     *
     * @dev The `repoToken` and `repoTokenAmount` parameters are optional and provide flexibility
     * to adjust the calculations to include the provided repoToken and amount. If `repoToken` is
     * set to `address(0)` or `repoTokenAmount` is `0`, the function calculates the cumulative
     * data without specific token adjustments.
     */
    function getCumulativeRepoTokenData(
        RepoTokenListData storage listData,
        ITermDiscountRateAdapter discountRateAdapter,
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    )
        internal
        view
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount,
            bool found
        )
    {
        // Return early if the list is empty
        if (listData.head == NULL_NODE) return (0, 0, false);

        // Initialize the current pointer to the head of the list
        address current = listData.head;
        while (current != NULL_NODE) {
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(
                address(this)
            );

            // Process if the repo token has a positive balance
            if (repoTokenBalance > 0) {
                // Add repoTokenAmount if the current token matches the specified repoToken
                if (repoToken == current) {
                    repoTokenBalance += repoTokenAmount;
                    found = true;
                }

                // Convert the repo token balance to base asset precision
                uint256 repoTokenBalanceInBaseAssetPrecision = RepoTokenUtils
                    .getNormalizedRepoTokenAmount(
                        current,
                        repoTokenBalance,
                        purchaseTokenPrecision,
                        discountRateAdapter.repoRedemptionHaircut(current)
                    );

                // Calculate the weighted time to maturity
                uint256 weightedTimeToMaturity = getRepoTokenWeightedTimeToMaturity(
                        current,
                        repoTokenBalanceInBaseAssetPrecision
                    );

                // Accumulate the results
                cumulativeWeightedTimeToMaturity += weightedTimeToMaturity;
                cumulativeRepoTokenAmount += repoTokenBalanceInBaseAssetPrecision;
            }

            // Move to the next repo token in the list
            current = _getNext(listData, current);
        }
    }

    /**
     * @notice Get the present value of repoTokens
     * @param listData The list data
     * @param discountRateAdapter The discount rate adapter
     * @param purchaseTokenPrecision The precision of the purchase token
     * @return totalPresentValue The total present value of the repoTokens
     * @dev  Aggregates the present value of all repoTokens in the list.
     */
    function getPresentValue(
        RepoTokenListData storage listData,
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 totalPresentValue) {
        // If the list is empty, return 0
        if (listData.head == NULL_NODE) return 0;

        address current = listData.head;
        while (current != NULL_NODE) {
            uint256 currentMaturity = getRepoTokenMaturity(current);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(
                address(this)
            );
            uint256 discountRate = discountRateAdapter.getDiscountRate(current);

            // Convert repo token balance to base asset precision
            // (ratePrecision * repoPrecision * purchasePrecision) / (repoPrecision * ratePrecision) = purchasePrecision
            uint256 repoTokenBalanceInBaseAssetPrecision = RepoTokenUtils
                .getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    discountRateAdapter.repoRedemptionHaircut(current)
                );

            // Calculate present value based on maturity
            if (currentMaturity > block.timestamp) {
                totalPresentValue += RepoTokenUtils.calculatePresentValue(
                    repoTokenBalanceInBaseAssetPrecision,
                    purchaseTokenPrecision,
                    currentMaturity,
                    discountRate
                );
            } else {
                totalPresentValue += repoTokenBalanceInBaseAssetPrecision;
            }

            // Move to the next token in the list
            current = _getNext(listData, current);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the time remaining until a repoToken matures
     * @param redemptionTimestamp The redemption timestamp of the repoToken
     * @return uint256 The time remaining (in seconds) until the repoToken matures
     *
     * @dev This function calculates the difference between the redemption timestamp and the current block timestamp
     * to determine how many seconds are left until the repoToken reaches its maturity.
     */
    function _getRepoTokenTimeToMaturity(
        uint256 redemptionTimestamp
    ) private view returns (uint256) {
        return redemptionTimestamp - block.timestamp;
    }

    /**
     * @notice Removes and redeems matured repoTokens from the list data
     * @param listData The list data
     *
     * @dev Iterates through the list of repoTokens and removes those that have matured. If a matured repoToken has a balance,
     * the function attempts to redeem it. This helps maintain the list by clearing out matured repoTokens and redeeming their balances.
     */
    function removeAndRedeemMaturedTokens(
        RepoTokenListData storage listData
    ) internal {
        if (listData.head == NULL_NODE) return;

        address current = listData.head;
        address prev = current;
        while (current != NULL_NODE) {
            address next;
            if (getRepoTokenMaturity(current) <= block.timestamp) {
                bool removeMaturedToken;
                uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(
                    address(this)
                );

                if (repoTokenBalance > 0) {
                    (, , address termRepoServicer, ) = ITermRepoToken(current)
                        .config();
                    try
                        ITermRepoServicer(termRepoServicer)
                            .redeemTermRepoTokens(
                                address(this),
                                repoTokenBalance
                            )
                    {
                        removeMaturedToken = true;
                    } catch {
                        // redemption failed, do not remove token from the list
                    }
                } else {
                    // already redeemed
                    removeMaturedToken = true;
                }

                next = _getNext(listData, current);

                if (removeMaturedToken) {
                    if (current == listData.head) {
                        listData.head = next;
                    }

                    listData.nodes[prev].next = next;
                    delete listData.nodes[current];
                    delete listData.discountRates[current];
                }
            } else {
                /// @dev early exit because list is sorted
                break;
            }

            prev = current;
            current = next;
        }
    }

    /**
     * @notice Validates a repoToken against specific criteria
     * @param listData The list data
     * @param repoToken The repoToken to validate
     * @param asset The address of the base asset
     * @return isRepoTokenValid Whether the repoToken is valid
     * @return redemptionTimestamp The redemption timestamp of the validated repoToken
     *
     * @dev Ensures the repoToken is deployed, matches the purchase token, is not matured, and meets collateral requirements.
     * Reverts with `InvalidRepoToken` if any validation check fails.
     */
    function validateRepoToken(
        RepoTokenListData storage listData,
        ITermRepoToken repoToken,
        address asset
    )
        internal
        view
        returns (bool isRepoTokenValid, uint256 redemptionTimestamp)
    {
        // Retrieve repo token configuration
        address purchaseToken;
        address collateralManager;
        (redemptionTimestamp, purchaseToken, , collateralManager) = repoToken
            .config();

        // Validate purchase token
        if (purchaseToken != asset) {
            return (false, redemptionTimestamp);
        }

        // Check if repo token has matured
        if (redemptionTimestamp < block.timestamp) {
            return (false, redemptionTimestamp);
        }

        // Validate collateral token ratios
        uint256 numTokens = ITermRepoCollateralManager(collateralManager)
            .numOfAcceptedCollateralTokens();
        for (uint256 i; i < numTokens; i++) {
            address currentToken = ITermRepoCollateralManager(collateralManager)
                .collateralTokens(i);
            uint256 minCollateralRatio = listData.collateralTokenParams[
                currentToken
            ];

            if (minCollateralRatio == 0) {
                return (false, redemptionTimestamp);
            } else if (
                ITermRepoCollateralManager(collateralManager)
                    .maintenanceCollateralRatios(currentToken) <
                minCollateralRatio
            ) {
                return (false, redemptionTimestamp);
            }
        }
        return (true, redemptionTimestamp);
    }

    /**
     * @notice Validate and insert a repoToken into the list data
     * @param listData The list data
     * @param repoToken The repoToken to validate and insert
     * @param discountRateAdapter The discount rate adapter
     * @param asset The address of the base asset
     * @return validRepoToken Whether the repoToken is valid
     * @return redemptionTimestamp The redemption timestamp of the validated repoToken
     */
    function validateAndInsertRepoToken(
        RepoTokenListData storage listData,
        ITermRepoToken repoToken,
        ITermDiscountRateAdapter discountRateAdapter,
        address asset
    ) internal returns (bool validRepoToken, uint256 redemptionTimestamp) {
        uint256 discountRate = listData.discountRates[address(repoToken)];
        if (discountRate != INVALID_AUCTION_RATE) {
            (redemptionTimestamp, , , ) = repoToken.config();

            // skip matured repoTokens
            if (redemptionTimestamp < block.timestamp) {
                return (false, redemptionTimestamp); //revert InvalidRepoToken(address(repoToken));
            }

            uint256 oracleRate;
            try
                discountRateAdapter.getDiscountRate(address(repoToken))
            returns (uint256 rate) {
                oracleRate = rate;
            } catch {}

            if (oracleRate != 0) {
                if (discountRate != oracleRate) {
                    listData.discountRates[address(repoToken)] = oracleRate;
                }
            }
        } else {
            try
                discountRateAdapter.getDiscountRate(address(repoToken))
            returns (uint256 rate) {
                discountRate = rate == 0 ? ZERO_AUCTION_RATE : rate;
            } catch {
                discountRate = INVALID_AUCTION_RATE;
                return (false, redemptionTimestamp);
            }

            bool isRepoTokenValid;

            (isRepoTokenValid, redemptionTimestamp) = validateRepoToken(
                listData,
                repoToken,
                asset
            );
            if (!isRepoTokenValid) {
                return (false, redemptionTimestamp);
            }
            insertSorted(listData, address(repoToken));
            listData.discountRates[address(repoToken)] = discountRate;
        }

        return (true, redemptionTimestamp);
    }

    /**
     * @notice Insert a repoToken into the list in a sorted manner
     * @param listData The list data
     * @param repoToken The address of the repoToken to be inserted
     *
     * @dev Inserts the `repoToken` into the `listData` while maintaining the list sorted by the repoTokens' maturity timestamps.
     * The function iterates through the list to find the correct position for the new `repoToken` and updates the pointers accordingly.
     */
    function insertSorted(
        RepoTokenListData storage listData,
        address repoToken
    ) internal {
        // Start at the head of the list
        address current = listData.head;

        // If the list is empty, set the new repoToken as the head
        if (current == NULL_NODE) {
            listData.head = repoToken;
            listData.nodes[repoToken].next = NULL_NODE;
            return;
        }

        uint256 maturityToInsert = getRepoTokenMaturity(repoToken);

        address prev;
        while (current != NULL_NODE) {
            // If the repoToken is already in the list, exit
            if (current == repoToken) {
                break;
            }

            uint256 currentMaturity = getRepoTokenMaturity(current);

            // Insert repoToken before current if its maturity is less than current maturity
            if (maturityToInsert < currentMaturity) {
                if (prev == NULL_NODE) {
                    listData.head = repoToken;
                } else {
                    listData.nodes[prev].next = repoToken;
                }
                listData.nodes[repoToken].next = current;
                break;
            }

            // Move to the next node
            address next = _getNext(listData, current);

            // If at the end of the list, insert repoToken after current
            if (next == NULL_NODE) {
                listData.nodes[current].next = repoToken;
                listData.nodes[repoToken].next = NULL_NODE;
                break;
            }

            prev = current;
            current = next;
        }
    }
}
