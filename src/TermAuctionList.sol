// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermAuction} from "./interfaces/term/ITermAuction.sol";
import {ITermAuctionOfferLocker} from "./interfaces/term/ITermAuctionOfferLocker.sol";
import {ITermController} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RepoTokenList, RepoTokenListData} from "./RepoTokenList.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";

struct PendingOffer {
    bytes32 offerId;
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

library TermAuctionList {
    using RepoTokenList for RepoTokenListData;

    bytes32 public constant NULL_NODE = bytes32(0);    

    function _getNext(TermAuctionListData storage listData, bytes32 current) private view returns (bytes32) {
        return listData.nodes[current].next;
    }

    function _count(TermAuctionListData storage listData) internal view returns (uint256 count) {
        if (listData.head == NULL_NODE) return 0;
        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            count++;
            current = _getNext(listData, current);
        }
    }

    function pendingOffers(TermAuctionListData storage listData) internal view returns (bytes32[] memory offers) {
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

    function insertPending(TermAuctionListData storage listData, PendingOffer memory pendingOffer) internal {
        bytes32 current = listData.head;
        bytes32 id = pendingOffer.offerId;

        if (current != NULL_NODE) {
            listData.nodes[id].next = current;
        }

        listData.head = id;
        listData.offers[id] = pendingOffer;
    }

    function removeCompleted(
        TermAuctionListData storage listData, 
        RepoTokenListData storage repoTokenListData,
        ITermController termController,
        address asset
    ) internal {
        /*
            offer submitted; auction still open => include offerAmount in totalValue (otherwise locked purchaseToken will be missing from TV)
            offer submitted; auction completed; !auctionClosed() => include offer.offerAmount in totalValue (because the offerLocker will have already deleted offer on completeAuction)
                                                            + even though repoToken has been transferred it hasn't been added to the repoTokenList
                                                            BUT only if it is new not a reopening
            offer submitted; auction completed; auctionClosed() => repoToken has been added to the repoTokenList
        */
        if (listData.head == NULL_NODE) return;

        bytes32 current = listData.head;
        bytes32 prev = current;
        while (current != NULL_NODE) {
            PendingOffer memory offer = listData.offers[current];
            bytes32 next = _getNext(listData, current);

            uint256 offerAmount = offer.offerLocker.lockedOffer(offer.offerId).amount;
            bool removeNode;
            bool insertRepoToken;

            if (offer.termAuction.auctionCompleted()) {
                removeNode = true;
                insertRepoToken = true;
            } else {
                if (offerAmount == 0) {
                    // auction canceled or deleted
                    removeNode = true;
                } else {
                    // offer pending, do nothing
                }

                if (offer.termAuction.auctionCancelledForWithdrawal()) {
                    removeNode = true;

                    // withdraw manually
                    bytes32[] memory offerIds = new bytes32[](1);
                    offerIds[0] = offer.offerId;
                    offer.offerLocker.unlockOffers(offerIds);
                }
            }

            if (removeNode) {
                if (current == listData.head) {
                    listData.head = next;
                }
                
                listData.nodes[prev].next = next;
                delete listData.nodes[current];
                delete listData.offers[current];
            }

            if (insertRepoToken) {
                repoTokenListData.validateAndInsertRepoToken(ITermRepoToken(offer.repoToken), termController, asset);
            }

            prev = current;
            current = next;
        }
    }

    function getPresentValue(
        TermAuctionListData storage listData, 
        RepoTokenListData storage repoTokenListData,
        ITermController termController,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 totalValue) {
        if (listData.head == NULL_NODE) return 0;
        
        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            PendingOffer memory offer = listData.offers[current];

            uint256 offerAmount = offer.offerLocker.lockedOffer(offer.offerId).amount;

            /// @dev offer processed, but auctionClosed not yet called and auction is new so repoToken not on List and wont be picked up
            /// checking repoTokenAuctionRates to make sure we are not double counting on re-openings
            if (offer.termAuction.auctionCompleted() && repoTokenListData.auctionRates[offer.repoToken] == 0) {
                uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils.getNormalizedRepoTokenAmount(
                    offer.repoToken, 
                    ITermRepoToken(offer.repoToken).balanceOf(address(this)),
                    purchaseTokenPrecision
                );
                totalValue += RepoTokenUtils.calculatePresentValue(
                    repoTokenAmountInBaseAssetPrecision, 
                    purchaseTokenPrecision, 
                    RepoTokenList.getRepoTokenMaturity(offer.repoToken), 
                    RepoTokenList.getAuctionRate(termController, ITermRepoToken(offer.repoToken))
                );
            } else {
                totalValue += offerAmount;
            }

            current = _getNext(listData, current);        
        }        
    }

    function getCumulativeOfferData(
        TermAuctionListData storage listData,
        RepoTokenListData storage repoTokenListData,
        ITermController termController,
        address repoToken, 
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 cumulativeWeightedTimeToMaturity, uint256 cumulativeOfferAmount, bool found) {
        if (listData.head == NULL_NODE) return (0, 0, false);

        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            PendingOffer memory offer = listData.offers[current];

            uint256 offerAmount;
            if (offer.repoToken == repoToken) {
                offerAmount = newOfferAmount;
                found = true;
            } else {
                offerAmount = offer.offerLocker.lockedOffer(offer.offerId).amount;

                /// @dev offer processed, but auctionClosed not yet called and auction is new so repoToken not on List and wont be picked up
                /// checking repoTokenAuctionRates to make sure we are not double counting on re-openings
                if (offer.termAuction.auctionCompleted() && repoTokenListData.auctionRates[offer.repoToken] == 0) {
                    // set offerAmount to pending offer amount
                    uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils.getNormalizedRepoTokenAmount(
                        offer.repoToken, 
                        ITermRepoToken(offer.repoToken).balanceOf(address(this)),
                        purchaseTokenPrecision
                    );
                    offerAmount = RepoTokenUtils.calculatePresentValue(
                        repoTokenAmountInBaseAssetPrecision, 
                        purchaseTokenPrecision, 
                        RepoTokenList.getRepoTokenMaturity(offer.repoToken), 
                        RepoTokenList.getAuctionRate(termController, ITermRepoToken(offer.repoToken))
                    );
                } 
            }

            if (offerAmount > 0) {
                uint256 weightedTimeToMaturity = RepoTokenList.getRepoTokenWeightedTimeToMaturity(
                    offer.repoToken, offerAmount
                );            

                cumulativeWeightedTimeToMaturity += weightedTimeToMaturity;
                cumulativeOfferAmount += offerAmount;
            }

            current = _getNext(listData, current);
        }
    }
}
