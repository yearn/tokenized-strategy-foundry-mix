// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermAuction} from "./interfaces/term/ITermAuction.sol";
import {ITermAuctionOfferLocker} from "./interfaces/term/ITermAuctionOfferLocker.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RepoTokenListData} from "./RepoTokenList.sol";

struct PendingOffer {
    bytes32 offerId;
    address repoToken;
    uint256 offerAmount;
    ITermAuction termAuction;
    ITermAuctionOfferLocker offerLocker;   
}

struct TermAuctionListNode {
    bytes32 next;
    bytes32 offerId;
    address repoToken;
    uint256 offerAmount;
    ITermAuction termAuction;
    ITermAuctionOfferLocker offerLocker;
}

struct TermAuctionListData {
    bytes32 head;
    mapping(bytes32 => TermAuctionListNode) nodes;
}

library TermAuctionList {
    bytes32 public constant NULL_NODE = bytes32(0);    

    function insertPending(TermAuctionListData storage listData, PendingOffer memory pendingOffer) internal {

    }

    function removeCompleted(TermAuctionListData storage listData) internal {
        if (listData.head == NULL_NODE) return;

        bytes32 current = listData.head;
        bytes32 prev = current;
        while (current != NULL_NODE) {
            TermAuctionListNode memory currentNode = listData.nodes[current];

            if (currentNode.termAuction.auctionCompleted()) {

            }

            prev = current;
            current = currentNode.next;
        }
    }

    function getPresentValue(
        TermAuctionListData storage listData, 
        RepoTokenListData storage repoTokenListData
    ) internal view returns (uint256 totalValue) {
        if (listData.head == NULL_NODE) return 0;
        
        bytes32 current = listData.head;
        while (current != NULL_NODE) {
            TermAuctionListNode memory currentNode = listData.nodes[current];

            uint256 offerAmount = currentNode.offerLocker.lockedOffer(currentNode.offerId).amount;

            /// @dev checking repoTokenAuctionRates to make sure we are not double counting on re-openings
            if (offerAmount == 0 && repoTokenListData.auctionRates[currentNode.repoToken] == 0) {
                totalValue += currentNode.offerAmount;
            } else {
                totalValue += offerAmount;
            }

            current = currentNode.next;        
        }        
    }
}
