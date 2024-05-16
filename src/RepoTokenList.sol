// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";
import {ITermRepoCollateralManager} from "./interfaces/term/ITermRepoCollateralManager.sol";
import {ITermController, TermAuctionResults} from "./interfaces/term/ITermController.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";

struct RepoTokenListNode {
    address next;
}

struct RepoTokenListData {
    address head;
    mapping(address => RepoTokenListNode) nodes;
    mapping(address => uint256) auctionRates;
    /// @notice keyed by collateral token
    mapping(address => uint256) collateralTokenParams;
}

library RepoTokenList {
    address public constant NULL_NODE = address(0);
    uint256 internal constant INVALID_AUCTION_RATE = 0;

    error InvalidRepoToken(address token);

    function _getRepoTokenMaturity(address repoToken) private view returns (uint256 redemptionTimestamp) {
        (redemptionTimestamp, , ,) = ITermRepoToken(repoToken).config();
    }

    function _getRepoTokenTimeToMaturity(uint256 redemptionTimestamp, address repoToken) private view returns (uint256) {
        return redemptionTimestamp - block.timestamp;
    }

    function _getNext(RepoTokenListData storage listData, address current) private view returns (address) {
        return listData.nodes[current].next;
    }

    function simulateWeightedTimeToMaturity(
        RepoTokenListData storage listData, 
        address repoToken, 
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision,
        uint256 liquidBalance
    ) internal view returns (uint256) {
        if (listData.head == NULL_NODE) return 0;

        uint256 cumulativeWeightedTimeToMaturity;  // in seconds
        uint256 cumulativeRepoTokenAmount;  // in purchase token precision
        address current = listData.head;
        bool found;
        while (current != NULL_NODE) {
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));

            if (repoTokenBalance > 0) {
                uint256 redemptionValue = ITermRepoToken(current).redemptionValue();
                uint256 repoTokenPrecision = 10**ERC20(current).decimals();

                if (repoToken == current) {
                    repoTokenBalance += repoTokenAmount;
                    found = true;
                }

                uint256 repoTokenBalanceInBaseAssetPrecision = 
                    (redemptionValue * repoTokenBalance * purchaseTokenPrecision) / 
                    (repoTokenPrecision * RepoTokenUtils.RATE_PRECISION);

                uint256 currentMaturity = _getRepoTokenMaturity(current);

                if (currentMaturity > block.timestamp) {
                    uint256 timeToMaturity = _getRepoTokenTimeToMaturity(currentMaturity, current);
                    // Not matured yet
                    cumulativeWeightedTimeToMaturity += 
                        timeToMaturity * repoTokenBalanceInBaseAssetPrecision;
                }
                cumulativeRepoTokenAmount += repoTokenBalanceInBaseAssetPrecision;
            }

            current = _getNext(listData, current);
        }

        /// @dev token is not found in the list (i.e. called from view function)
        if (!found && repoToken != address(0)) {
            uint256 repoTokenPrecision = 10**ERC20(repoToken).decimals();
            uint256 redemptionValue = ITermRepoToken(repoToken).redemptionValue();
            uint256 repoTokenAmountInBaseAssetPrecision =
                (redemptionValue * repoTokenAmount * purchaseTokenPrecision) / 
                (repoTokenPrecision * RepoTokenUtils.RATE_PRECISION);

            cumulativeRepoTokenAmount += repoTokenAmountInBaseAssetPrecision;
            uint256 maturity = _getRepoTokenMaturity(repoToken);
            if (maturity > block.timestamp) {
                uint256 timeToMaturity = _getRepoTokenTimeToMaturity(maturity, repoToken);
                cumulativeWeightedTimeToMaturity += 
                    timeToMaturity * repoTokenAmountInBaseAssetPrecision;
            }
        }

        /// @dev avoid div by 0
        if (cumulativeRepoTokenAmount == 0 && liquidBalance == 0) {
            return 0;
        }

        // time * purchaseTokenPrecision / purchaseTokenPrecision
        return cumulativeWeightedTimeToMaturity / (cumulativeRepoTokenAmount + liquidBalance);
    }

    function removeAndRedeemMaturedTokens(RepoTokenListData storage listData) internal {
        if (listData.head == NULL_NODE) return;

        address current = listData.head;
        address prev = current;
        while (current != NULL_NODE) {
            address next;
            if (_getRepoTokenMaturity(current) < block.timestamp) {
                next = _getNext(listData, current);

                if (current == listData.head) {
                    listData.head = next;
                }
                
                listData.nodes[prev].next = next;
                delete listData.nodes[current];
                delete listData.auctionRates[current];

                uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));

                if (repoTokenBalance > 0) {
                    (, , address termRepoServicer,) = ITermRepoToken(current).config();
                    ITermRepoServicer(termRepoServicer).redeemTermRepoTokens(address(this), repoTokenBalance);
                }
            } else {
                /// @dev early exit because list is sorted
                break;
            }

            prev = current;
            current = next;
        }        
    }

    function _auctionRate(ITermController termController, ITermRepoToken repoToken) private view returns (uint256) {
        TermAuctionResults memory results = termController.getTermAuctionResults(repoToken.termRepoId());

        uint256 len = results.auctionMetadata.length;

        require(len > 0);

        return results.auctionMetadata[len - 1].auctionClearingRate;
    }

    function validateRepoToken(
        RepoTokenListData storage listData,
        ITermRepoToken repoToken,
        ITermController termController,
        address asset
    ) internal view returns (uint256 redemptionTimestamp) {
        if (!termController.isTermDeployed(address(repoToken))) {
            revert InvalidRepoToken(address(repoToken));
        }

        address purchaseToken;
        address collateralManager;
        (redemptionTimestamp, purchaseToken, , collateralManager) = repoToken.config();
        if (purchaseToken != address(asset)) {
            revert InvalidRepoToken(address(repoToken));
        }

        // skip matured repo tokens
        if (redemptionTimestamp < block.timestamp) {
            revert InvalidRepoToken(address(repoToken));
        }

        uint256 numTokens = ITermRepoCollateralManager(collateralManager).numOfAcceptedCollateralTokens();

        for (uint256 i; i < numTokens; i++) {
            address currentToken = ITermRepoCollateralManager(collateralManager).collateralTokens(i);
            uint256 minCollateralRatio = listData.collateralTokenParams[currentToken];

            if (minCollateralRatio == 0) {
                revert InvalidRepoToken(address(repoToken));
            } else if (
                ITermRepoCollateralManager(collateralManager).maintenanceCollateralRatios(currentToken) < minCollateralRatio
            ) {
                revert InvalidRepoToken(address(repoToken));
            }
        }
    }

    function validateAndInsertRepoToken(
        RepoTokenListData storage listData, 
        ITermRepoToken repoToken,
        ITermController termController,
        address asset
    ) internal returns (uint256 auctionRate, uint256 redemptionTimestamp) 
    {
        auctionRate = listData.auctionRates[address(repoToken)];
        if (auctionRate != INVALID_AUCTION_RATE) {
            (redemptionTimestamp, , ,) = repoToken.config();

            // skip matured repo tokens
            if (redemptionTimestamp < block.timestamp) {
                revert InvalidRepoToken(address(repoToken));
            }

            uint256 oracleRate = _auctionRate(termController, repoToken);
            if (oracleRate != INVALID_AUCTION_RATE) {
                if (auctionRate != oracleRate) {
                    listData.auctionRates[address(repoToken)] = oracleRate;
                }
            }
        } else {
            auctionRate = _auctionRate(termController, repoToken);

            redemptionTimestamp = validateRepoToken(listData, repoToken, termController, asset);

            insertSorted(listData, address(repoToken));
            listData.auctionRates[address(repoToken)] = auctionRate;
        }
    }

    function insertSorted(RepoTokenListData storage listData, address repoToken) internal {
        address current = listData.head;

        if (current == NULL_NODE) {
            listData.head = repoToken;
            return;
        }

        address prev;
        while (current != NULL_NODE) {

            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 maturityToInsert = _getRepoTokenMaturity(repoToken);

            if (maturityToInsert <= currentMaturity) {
                if (prev == NULL_NODE) {
                    listData.head = repoToken;
                } else {
                    listData.nodes[prev].next = repoToken;
                }
                listData.nodes[repoToken].next = current;
                break;
            }

            prev = current;
            current = _getNext(listData, current);
        }
    }

    function getPresentValue(
        RepoTokenListData storage listData, 
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 totalPresentValue) {
        if (listData.head == NULL_NODE) return 0;
        
        address current = listData.head;
        while (current != NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));
            uint256 repoTokenPrecision = 10**ERC20(current).decimals();
            uint256 auctionRate = listData.auctionRates[current];

            // (ratePrecision * repoPrecision * purchasePrecision) / (repoPrecision * ratePrecision) = purchasePrecision
            uint256 repoTokenBalanceInBaseAssetPrecision = 
                (ITermRepoToken(current).redemptionValue() * repoTokenBalance * purchaseTokenPrecision) / 
                (repoTokenPrecision * RepoTokenUtils.RATE_PRECISION);

            if (currentMaturity > block.timestamp) {
                totalPresentValue += RepoTokenUtils.calculatePresentValue(
                    repoTokenBalanceInBaseAssetPrecision, purchaseTokenPrecision, currentMaturity, auctionRate
                );
            } else {
                totalPresentValue += repoTokenBalanceInBaseAssetPrecision;
            }

            current = _getNext(listData, current);                    
        }    
    }
}
