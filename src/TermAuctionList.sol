// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermAuction} from "./interfaces/term/ITermAuction.sol";
import {ITermAuctionOfferLocker} from "./interfaces/term/ITermAuctionOfferLocker.sol";
import {ITermController} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RepoTokenList, RepoTokenListData} from "./RepoTokenList.sol";

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
        if (listData.head == NULL_NODE) return;

        bytes32 current = listData.head;
        bytes32 prev = current;
        while (current != NULL_NODE) {
            PendingOffer memory offer = listData.offers[current];
            bytes32 next = _getNext(listData, current);

            if (offer.termAuction.auctionCompleted()) {
                if (current == listData.head) {
                    listData.head = next;
                }
                
                listData.nodes[prev].next = next;
                delete listData.nodes[current];
                delete listData.offers[current];

                repoTokenListData.validateAndInsertRepoToken(ITermRepoToken(offer.repoToken), termController, asset);
            }

            prev = current;
            current = next;
        }
    }

    function getPresentValue(
        TermAuctionListData storage listData, 
        RepoTokenListData storage repoTokenListData
    ) internal view returns (uint256 totalValue) {
        if (listData.head == NULL_NODE) return 0;
        
        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            PendingOffer memory offer = listData.offers[current];

            uint256 offerAmount = offer.offerLocker.lockedOffer(offer.offerId).amount;

            /// @dev checking repoTokenAuctionRates to make sure we are not double counting on re-openings
            if (offerAmount == 0 && repoTokenListData.auctionRates[offer.repoToken] == 0) {
                totalValue += offer.offerAmount;
            } else {
                totalValue += offerAmount;
            }

            current = _getNext(listData, current);        
        }        
    }
}
