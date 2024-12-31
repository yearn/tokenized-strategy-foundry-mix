// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermController} from "./interfaces/term/ITermController.sol";
import {ITermAuction} from "./interfaces/term/ITermAuction.sol";
import {ITermAuctionOfferLocker} from "./interfaces/term/ITermAuctionOfferLocker.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";
import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {RepoTokenList, RepoTokenListData} from "./RepoTokenList.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";

// In-storage representation of an offer object
struct PendingOffer {
    address repoToken;
    uint256 offerAmount;
    ITermAuction termAuction;
    ITermAuctionOfferLocker offerLocker;
}

struct TermAuctionListNode {
    bytes32 next;
}

struct TermAuctionListData {
    bytes32 head;
    mapping(bytes32 => TermAuctionListNode) nodes;
    mapping(bytes32 => PendingOffer) offers;
}

/*//////////////////////////////////////////////////////////////
                        LIBRARY: TermAuctionList
//////////////////////////////////////////////////////////////*/

library TermAuctionList {
    using RepoTokenList for RepoTokenListData;

    bytes32 internal constant NULL_NODE = bytes32(0);

    /*//////////////////////////////////////////////////////////////
                        PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get the next node in the list
     * @param listData The list data
     * @param current The current node
     * @return The next node
     */
    function _getNext(
        TermAuctionListData storage listData,
        bytes32 current
    ) private view returns (bytes32) {
        return listData.nodes[current].next;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Count the number of nodes in the list
     * @param listData The list data
     * @return count The number of nodes in the list
     */
    function _count(
        TermAuctionListData storage listData
    ) internal view returns (uint256 count) {
        if (listData.head == NULL_NODE) return 0;
        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            count++;
            current = _getNext(listData, current);
        }
    }

    /**
     * @notice Retrieves an array of offer IDs representing the pending offers
     * @param listData The list data
     * @return offers An array of offer IDs representing the pending offers
     *
     * @dev This function iterates through the list of offers and gathers their IDs into an array of `bytes32`.
     * This makes it easier to process and manage the pending offers.
     */
    function pendingOffers(
        TermAuctionListData storage listData
    ) internal view returns (bytes32[] memory offers) {
        uint256 count = _count(listData);
        if (count > 0) {
            offers = new bytes32[](count);
            uint256 i;
            bytes32 current = listData.head;
            while (current != NULL_NODE) {
                offers[i++] = current;
                current = _getNext(listData, current);
            }
        }
    }

    /**
     * @notice Inserts a new pending offer into the list data
     * @param listData The list data
     * @param offerId The ID of the offer to be inserted
     * @param pendingOffer The `PendingOffer` struct containing details of the offer to be inserted
     *
     * @dev This function inserts a new pending offer while maintaining the list sorted by auction address.
     * The function iterates through the list to find the correct position for the new `offerId` and updates the pointers accordingly.
     */
    function insertPending(
        TermAuctionListData storage listData,
        bytes32 offerId,
        PendingOffer memory pendingOffer
    ) internal {
        bytes32 current = listData.head;
        require(!pendingOffer.termAuction.auctionCompleted());

        // If the list is empty, set the new repoToken as the head
        if (current == NULL_NODE) {
            listData.head = offerId;
            listData.nodes[offerId].next = NULL_NODE;
            listData.offers[offerId] = pendingOffer;
            return;
        }

        bytes32 prev;
        while (current != NULL_NODE) {
            // If the offerId is already in the list, exit
            if (current == offerId) {
                break;
            }

            address currentAuction = address(
                listData.offers[current].termAuction
            );
            address auctionToInsert = address(pendingOffer.termAuction);

            // Insert offer before current if the auction address to insert is less than current auction address
            if (auctionToInsert < currentAuction) {
                if (prev == NULL_NODE) {
                    listData.head = offerId;
                } else {
                    listData.nodes[prev].next = offerId;
                }
                listData.nodes[offerId].next = current;
                break;
            }

            // Move to the next node
            bytes32 next = _getNext(listData, current);

            // If at the end of the list, insert repoToken after current
            if (next == NULL_NODE) {
                listData.nodes[current].next = offerId;
                listData.nodes[offerId].next = NULL_NODE;
                break;
            }

            prev = current;
            current = next;
        }
        listData.offers[offerId] = pendingOffer;
    }

    /**
     * @notice Removes completed or cancelled offers from the list data and processes the corresponding repoTokens
     * @param listData The list data
     * @param repoTokenListData The repoToken list data
     * @param discountRateAdapter The discount rate adapter
     * @param asset The address of the asset
     *
     * @dev This function iterates through the list of offers and removes those that are completed or cancelled.
     * It processes the corresponding repoTokens by validating and inserting them if necessary. This helps maintain
     * the list by clearing out inactive offers and ensuring repoTokens are correctly processed.
     */
    function removeCompleted(
        TermAuctionListData storage listData,
        RepoTokenListData storage repoTokenListData,
        ITermDiscountRateAdapter discountRateAdapter,
        address asset
    ) internal {
        // Return if the list is empty
        if (listData.head == NULL_NODE) return;

        bytes32 current = listData.head;
        bytes32 prev = current;
        while (current != NULL_NODE) {
            PendingOffer memory offer = listData.offers[current];
            bytes32 next = _getNext(listData, current);

            uint256 offerAmount = offer.offerLocker.lockedOffer(current).amount;
            bool removeNode;

            if (offer.termAuction.auctionCompleted()) {
                // If auction is completed and closed, mark for removal and prepare to insert repo token
                removeNode = true;
                // Auction still open => include offerAmount in totalValue
                // (otherwise locked purchaseToken will be missing from TV)
                // Auction completed but not closed => include offer.offerAmount in totalValue
                // because the offerLocker will have already removed the offer.
                // This applies if the repoToken hasn't been added to the repoTokenList
                // (only for new auctions, not reopenings).
                (
                    bool isValidRepoToken,
                    uint256 redemptionTimestamp
                ) = repoTokenListData.validateAndInsertRepoToken(
                        ITermRepoToken(offer.repoToken),
                        discountRateAdapter,
                        asset
                    );
                if (
                    !isValidRepoToken && block.timestamp > redemptionTimestamp
                ) {
                    ITermRepoToken repoToken = ITermRepoToken(offer.repoToken);
                    (, , address repoServicerAddr, ) = repoToken.config();
                    ITermRepoServicer repoServicer = ITermRepoServicer(
                        repoServicerAddr
                    );
                    try
                        repoServicer.redeemTermRepoTokens(
                            address(this),
                            repoToken.balanceOf(address(this))
                        )
                    {} catch {}
                }
            } else {
                if (offer.termAuction.auctionCancelledForWithdrawal()) {
                    // If auction was canceled for withdrawal, remove the node and unlock offers manually
                    bytes32[] memory offerIds = new bytes32[](1);
                    offerIds[0] = current;
                    try offer.offerLocker.unlockOffers(offerIds) {
                        // unlocking offer in this scenario withdraws offer amount
                        removeNode = true;
                    } catch {
                        removeNode = false;
                    }
                } else {
                    if (offerAmount == 0) {
                        // If offer amount is zero, it indicates the auction was canceled or deleted
                        removeNode = true;
                    }
                }
            }

            if (removeNode) {
                // Update the list to remove the current node
                delete listData.nodes[current];
                delete listData.offers[current];
                if (current == listData.head) {
                    listData.head = next;
                } else {
                    listData.nodes[prev].next = next;
                    current = prev;
                }
            }

            // Move to the next node
            prev = current;
            current = next;
        }
    }

    /**
     * @notice Calculates the total present value of all relevant offers related to a specified repoToken
     * @param listData The list data
     * @param repoTokenListData The repoToken list data
     * @param discountRateAdapter The discount rate adapter
     * @param purchaseTokenPrecision The precision of the purchase token
     * @param repoTokenToMatch The address of the repoToken to match (optional)
     * @return totalValue The total present value of the offers
     *
     * @dev This function calculates the present value of offers in the list. If `repoTokenToMatch` is provided,
     * it will filter the calculations to include only the specified repoToken. If `repoTokenToMatch` is not provided,
     * it will aggregate the present value of all repoTokens in the list. This provides flexibility for both aggregate
     * and specific token evaluations.
     */
    function getPresentValue(
        TermAuctionListData storage listData,
        RepoTokenListData storage repoTokenListData,
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) internal view returns (uint256 totalValue) {
        // Return 0 if the list is empty
        if (listData.head == NULL_NODE) return 0;
        address edgeCaseAuction; // NOTE: handle edge case, assumes that pendingOffer is properly sorted by auction address

        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            PendingOffer storage offer = listData.offers[current];

            // Filter by specific repo token if provided, address(0) bypasses this filter
            if (
                repoTokenToMatch != address(0) &&
                offer.repoToken != repoTokenToMatch
            ) {
                // Not a match, skip
                // Move to the next token in the list
                current = _getNext(listData, current);
                continue;
            }

            uint256 offerAmount = offer.offerLocker.lockedOffer(current).amount;

            // Handle new or unseen repo tokens
            /// @dev offer processed, but auctionClosed not yet called and auction is new so repoToken not on List and wont be picked up
            /// checking repoTokendiscountRates to make sure we are not double counting on re-openings
            if (
                offer.termAuction.auctionCompleted() &&
                repoTokenListData.discountRates[offer.repoToken] == 0
            ) {
                if (edgeCaseAuction != address(offer.termAuction)) {
                    uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
                        .getNormalizedRepoTokenAmount(
                            offer.repoToken,
                            ITermRepoToken(offer.repoToken).balanceOf(
                                address(this)
                            ),
                            purchaseTokenPrecision,
                            discountRateAdapter.repoRedemptionHaircut(
                                offer.repoToken
                            )
                        );
                    totalValue += RepoTokenUtils.calculatePresentValue(
                        repoTokenAmountInBaseAssetPrecision,
                        purchaseTokenPrecision,
                        RepoTokenList.getRepoTokenMaturity(offer.repoToken),
                        discountRateAdapter.getDiscountRate(offer.repoToken)
                    );

                    // Mark the edge case auction as processed to avoid double counting
                    // since multiple offers can be tied to the same auction, we need to mark
                    // the edge case auction as processed to avoid double counting
                    edgeCaseAuction = address(offer.termAuction);
                }
            } else {
                // Add the offer amount to the total value
                totalValue += offerAmount;
            }

            // Move to the next token in the list
            current = _getNext(listData, current);
        }
    }

    /**
     * @notice Get cumulative offer data for a specified repoToken
     * @param listData The list data
     * @param repoTokenListData The repoToken list data
     * @param discountRateAdapter The discount rate adapter
     * @param repoToken The address of the repoToken (optional)
     * @param newOfferAmount The new offer amount for the specified repoToken
     * @param purchaseTokenPrecision The precision of the purchase token
     * @return cumulativeWeightedTimeToMaturity The cumulative weighted time to maturity
     * @return cumulativeOfferAmount The cumulative repoToken amount
     * @return found Whether the specified repoToken was found in the list
     *
     * @dev This function calculates cumulative data for all offers in the list. The `repoToken` and `newOfferAmount`
     * parameters are optional and provide flexibility to include the newOfferAmount for a specified repoToken in the calculation.
     * If `repoToken` is set to `address(0)` or `newOfferAmount` is `0`, the function calculates the cumulative data
     * without adjustments.
     */
    function getCumulativeOfferData(
        TermAuctionListData storage listData,
        RepoTokenListData storage repoTokenListData,
        ITermDiscountRateAdapter discountRateAdapter,
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    )
        internal
        view
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        )
    {
        // If the list is empty, return 0s and false
        if (listData.head == NULL_NODE) return (0, 0, false);
        address edgeCaseAuction; // NOTE: handle edge case, assumes that pendingOffer is properly sorted by auction address

        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            PendingOffer storage offer = listData.offers[current];

            uint256 offerAmount;
            if (offer.repoToken == repoToken) {
                offerAmount = newOfferAmount;
                found = true;
            } else {
                // Retrieve the current offer amount from the offer locker
                offerAmount = offer.offerLocker.lockedOffer(current).amount;

                // Handle new repo tokens or reopening auctions
                /// @dev offer processed, but auctionClosed not yet called and auction is new so repoToken not on List and wont be picked up
                /// checking repoTokendiscountRates to make sure we are not double counting on re-openings
                if (
                    offer.termAuction.auctionCompleted() &&
                    repoTokenListData.discountRates[offer.repoToken] == 0
                ) {
                    // use normalized repoToken amount if repoToken is not in the list
                    if (edgeCaseAuction != address(offer.termAuction)) {
                        offerAmount = RepoTokenUtils
                            .getNormalizedRepoTokenAmount(
                                offer.repoToken,
                                ITermRepoToken(offer.repoToken).balanceOf(
                                    address(this)
                                ),
                                purchaseTokenPrecision,
                                discountRateAdapter.repoRedemptionHaircut(
                                    offer.repoToken
                                )
                            );

                        // Mark the edge case auction as processed to avoid double counting
                        // since multiple offers can be tied to the same auction, we need to mark
                        // the edge case auction as processed to avoid double counting
                        edgeCaseAuction = address(offer.termAuction);
                    }
                }
            }

            if (offerAmount > 0) {
                // Calculate weighted time to maturity
                uint256 weightedTimeToMaturity = RepoTokenList
                    .getRepoTokenWeightedTimeToMaturity(
                        offer.repoToken,
                        offerAmount
                    );

                cumulativeWeightedTimeToMaturity += weightedTimeToMaturity;
                cumulativeOfferAmount += offerAmount;
            }

            // Move to the next token in the list
            current = _getNext(listData, current);
        }
    }
}
