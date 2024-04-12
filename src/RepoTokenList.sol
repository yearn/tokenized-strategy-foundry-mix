// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";

struct ListNode {
    address next;
}

struct ListData {
    address head;
    mapping(address => ListNode) nodes;
}

library RepoTokenList {
    function _getRepoTokenMaturity(address repoToken) private view returns (uint256 redemptionTimestamp) {
        (redemptionTimestamp, ) = ITermRepoToken(repoToken).config();
    }

    function _getRepoTokenTimeToMaturity(address repoToken) private view returns (uint256) {
        return _getRepoTokenMaturity(repoToken) - block.timestamp;
    }

    function _getNext(ListData storage listData, address current) private view returns (address) {
        return listData.nodes[current].next;
    }

    function getWeightedTimeToMaturity(ListData storage listData, address repoToken, uint256 amount) internal view returns (uint256) {
        if (listData.head == NULL_NODE) return 0;

        uint256 cumulativeWeightedMaturityTimestamp;
        uint256 cumulativeRepoTokenAmount;
        address current = listData.head;
        while (current != NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));

            if (currentMaturity > block.timestamp) {
                uint256 timeToMaturity = _getRepoTokenTimeToMaturity(current);
                // Not matured yet
                cumulativeWeightedMaturityTimestamp += timeToMaturity * repoTokenBalance / repoTokenPrecision;
            }
            cumulativeRepoTokenAmount += repoTokenBalance;

            current = _getNext(current);
        }

        if (repoToken != address(0)) {
            cumulativeWeightedMaturityTimestamp += _getRepoTokenTimeToMaturity(repoToken) * amount;
            cumulativeRepoTokenAmount += amount;
        }

        uint256 excessLiquidity = _assetBalance(address(this)) * repoTokenPrecision / PURCHASE_TOKEN_PRECISION;

        /// @dev avoid div by 0
        if (cumulativeRepoTokenAmount == 0 && excessLiquidity == 0) {
            return 0;
        }

        return cumulativeWeightedMaturityTimestamp * repoTokenPrecision / (cumulativeRepoTokenAmount + excessLiquidity);
    }

    function removeAndRedeemMaturedTokens(ListData storage listData, address repoServicer, uint256 amount) internal {
        if (listData.head == NULL_NODE) return;

        address current = listData.head;
        address prev = current;
        while (current != NULL_NODE) {
            address next;

            if (_getRepoTokenMaturity(current) >= block.timestamp) {
                next = _getNext(current);

                if (current == listData.head) {
                    listData.head = next;
                }
                
                listData.nodes[prev].next = next;
                delete listData.nodes[current];
                delete repoTokenExists[current];

                ITermRepoServicer(repoServicer).redeemTermRepoTokens(address(this), amount);
            } else {
                /// @dev early exit because list is sorted
                break;
            }

            prev = current;
            current = _getNext(current);
        }        
    }

    function insertSorted(ListData storage listData, address repoToken) internal {
        address current = listData.head;

        if (current == NULL_NODE) {
            listData.head = repoToken;
            return;
        }

        address prev;
        while (current != address(0)) {

            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 maturityToInsert = _getRepoTokenMaturity(repoToken);

            if (maturityToInsert <= currentMaturity) {
                if (prev == address(0)) {
                    listData.head = repoToken;
                } else {
                    listData.nodes[prev].next = repoToken;
                }
                listData.nodes[repoToken].next = current;
                break;
            }

            prev = current;
            current = _getNext(current);
        }
    }
}
