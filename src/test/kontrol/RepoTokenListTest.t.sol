pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";
import "src/TermAuctionList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/TermAuction.sol";
import "src/test/kontrol/TermAuctionOfferLocker.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract RepoTokenListTest is KontrolTest {
    using RepoTokenList for RepoTokenListData;

    RepoTokenListData _repoTokenList;

    /**
     * Deploy a new RepoToken with symbolic storage.
     */
    function _newRepoToken() internal returns (address) {
        RepoToken repoToken = new RepoToken();
        repoToken.initializeSymbolic();

        return address(repoToken);
    }

    /**
     * Return the maturity timestamp of the given RepoToken.
     */
    function _getRepoTokenMaturity(
        address repoToken
    ) internal view returns (uint256 redemptionTimestamp) {
        (redemptionTimestamp, , , ) = ITermRepoToken(repoToken).config();
    }

    /**
     * Return the this contract's balance in the given RepoToken.
     */
    function _getRepoTokenBalance(
        address repoToken
    ) internal view returns (uint256) {
        return ITermRepoToken(repoToken).balanceOf(address(this));
    }

    function _initializeRepoTokenListEmpty() internal {
        _repoTokenList.head = RepoTokenList.NULL_NODE;
    }

    /**
     * Initialize _repoTokenList to a RepoTokenList of arbitrary size, where all
     * items are distinct RepoTokens with symbolic storage.
     */
    function _initializeRepoTokenList() internal {
        address previous = RepoTokenList.NULL_NODE;

        while (kevm.freshBool() != 0) {
            address current = _newRepoToken();

            if (previous == RepoTokenList.NULL_NODE) {
                _repoTokenList.head = current;
            } else {
                _repoTokenList.nodes[previous].next = current;
            }

            previous = current;
        }

        if (previous == RepoTokenList.NULL_NODE) {
            _repoTokenList.head = RepoTokenList.NULL_NODE;
        } else {
            _repoTokenList.nodes[previous].next = RepoTokenList.NULL_NODE;
        }
    }

    /**
     * Count the number of nodes in the list.
     *
     * Note that this function guarantees the following postconditions:
     * - The head of the list is NULL_NODE iff the count is 0.
     * - If the count is N, the Nth node in the list is followed by NULL_NODE.
     */
    function _countNodesInList() internal view returns (uint256) {
        uint256 count = 0;
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            ++count;
            current = _repoTokenList.nodes[current].next;
        }

        return count;
    }

    /**
     * Return true if the given RepoToken is in the list, and false otherwise.
     */
    function _repoTokenInList(address repoToken) internal view returns (bool) {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            if (current == repoToken) {
                return true;
            }

            current = _repoTokenList.nodes[current].next;
        }

        return false;
    }

    function _repoTokensListToArray(
        uint256 length
    ) internal view returns (address[] memory repoTokens) {
        address current = _repoTokenList.head;
        uint256 i;
        repoTokens = new address[](length);

        while (current != RepoTokenList.NULL_NODE) {
            repoTokens[i++] = current;
            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Initialize the TermDiscountRateAdapter to a symbolic state, ensuring that
     * it has a symbolic discount rate for every token in the RepoTokenList.
     */
    function _initializeDiscountRateAdapter(
        TermDiscountRateAdapter discountRateAdapter
    ) internal {
        discountRateAdapter.initializeSymbolic();

        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            discountRateAdapter.initializeSymbolicParamsFor(current);

            current = _repoTokenList.nodes[current].next;
        }
    }

    // Calculates the cumulative data assuming that no tokens have matured
    function _cumulativeRepoTokenDataNotMatured(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    )
        internal
        view
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount
        )
    {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            (uint256 currentMaturity, , , ) = ITermRepoToken(current).config();
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(
                address(this)
            );
            uint256 repoRedemptionHaircut = discountRateAdapter
                .repoRedemptionHaircut(current);
            uint256 timeToMaturity = currentMaturity - block.timestamp;

            uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
                .getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    repoRedemptionHaircut
                );

            uint256 weightedTimeToMaturity = timeToMaturity *
                repoTokenAmountInBaseAssetPrecision;

            cumulativeWeightedTimeToMaturity += weightedTimeToMaturity;
            cumulativeRepoTokenAmount += repoTokenAmountInBaseAssetPrecision;

            current = _repoTokenList.nodes[current].next;
        }
    }

    // Calculates the total present of matured tokens and removes them from the list
    function _filterMaturedTokensGetTotalValue(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal returns (uint256) {
        address current = _repoTokenList.head;
        address prev = current;
        uint256 totalPresentValue = 0;

        while (current != RepoTokenList.NULL_NODE) {
            address next = _repoTokenList.nodes[current].next;

            (uint256 currentMaturity, , , ) = ITermRepoToken(current).config();

            if (currentMaturity <= block.timestamp) {
                uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(
                    address(this)
                );
                uint256 repoRedemptionHaircut = discountRateAdapter
                    .repoRedemptionHaircut(current);

                totalPresentValue += RepoTokenUtils
                    .getNormalizedRepoTokenAmount(
                        current,
                        repoTokenBalance,
                        purchaseTokenPrecision,
                        repoRedemptionHaircut
                    );

                if (current == _repoTokenList.head) {
                    _repoTokenList.head = next;
                } else {
                    _repoTokenList.nodes[prev].next = next;
                    current = prev;
                }
            }

            prev = current;
            current = next;
        }

        return totalPresentValue;
    }

    // Calculates the total present value for non matured tokens
    function _totalPresentValueNotMatured(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256) {
        address current = _repoTokenList.head;
        uint256 totalPresentValue = 0;

        while (current != RepoTokenList.NULL_NODE) {
            (uint256 currentMaturity, , , ) = ITermRepoToken(current).config();
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(
                address(this)
            );
            uint256 repoRedemptionHaircut = discountRateAdapter
                .repoRedemptionHaircut(current);
            uint256 discountRate = discountRateAdapter.getDiscountRate(current);
            uint256 timeToMaturity = currentMaturity - block.timestamp;

            uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
                .getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    repoRedemptionHaircut
                );

            uint256 timeLeftToMaturityDayFraction = (timeToMaturity *
                purchaseTokenPrecision) / 360 days;

            uint256 presentValue = (repoTokenAmountInBaseAssetPrecision *
                purchaseTokenPrecision) /
                (purchaseTokenPrecision +
                    ((discountRate * timeLeftToMaturityDayFraction) / 1e18));

            totalPresentValue += presentValue;

            current = _repoTokenList.nodes[current].next;
        }

        return totalPresentValue;
    }

    function _establishInsertListPreservation(
        address insertedRepoToken,
        address[] memory repoTokens,
        uint256 repoTokensCount
    ) internal view {
        address current = _repoTokenList.head;
        uint256 i = 0;

        if (insertedRepoToken != address(0)) {
            while (current != RepoTokenList.NULL_NODE && i < repoTokensCount) {
                if (current != repoTokens[i]) {
                    assert(current == insertedRepoToken);
                    current = _repoTokenList.nodes[current].next;
                    break;
                }
                i++;
                current = _repoTokenList.nodes[current].next;
            }

            if (current != RepoTokenList.NULL_NODE && i == repoTokensCount) {
                assert(current == insertedRepoToken);
            }
        }

        while (current != RepoTokenList.NULL_NODE && i < repoTokensCount) {
            assert(current == repoTokens[i++]);
            current = _repoTokenList.nodes[current].next;
        }
    }

    function _establishRemoveListPreservation(
        address[] memory repoTokens,
        uint256 repoTokensCount
    ) internal view {
        address current = _repoTokenList.head;
        uint256 i = 0;

        while (current != RepoTokenList.NULL_NODE && i < repoTokensCount) {
            if (current == repoTokens[i++]) {
                current = _repoTokenList.nodes[current].next;
            }
        }

        assert(current == RepoTokenList.NULL_NODE);
    }

    /**
     * Assume or assert that the tokens in the list are sorted by maturity.
     */
    function _establishSortedByMaturity(Mode mode) internal view {
        address previous = RepoTokenList.NULL_NODE;
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            if (previous != RepoTokenList.NULL_NODE) {
                uint256 previousMaturity = _getRepoTokenMaturity(previous);
                uint256 currentMaturity = _getRepoTokenMaturity(current);
                _establish(mode, previousMaturity <= currentMaturity);
            }

            previous = current;
            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no duplicate tokens in the list.
     */
    function _establishNoDuplicateTokens(Mode mode) internal view {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            address other = _repoTokenList.nodes[current].next;

            while (other != RepoTokenList.NULL_NODE) {
                _establish(mode, current != other);
                other = _repoTokenList.nodes[other].next;
            }

            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no tokens in the list have matured
     * (i.e. all token maturities are greater than the current timestamp).
     */
    function _establishNoMaturedTokens(Mode mode) internal view {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);

            _establish(mode, block.timestamp < currentMaturity);

            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that all tokens in the list have balance > 0.
     */
    function _establishPositiveBalance(Mode mode) internal view {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            uint256 repoTokenBalance = _getRepoTokenBalance(current);

            _establish(mode, 0 < repoTokenBalance);

            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Weaker version of the above invariant that allows matured tokens to have
     * a balance of 0.
     *
     * Note: This is equivalent to the above invariant if the NoMaturedTokens
     * invariant also holds.
     */
    function _establishPositiveBalanceForNonMaturedTokens(
        Mode mode
    ) internal view {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 repoTokenBalance = _getRepoTokenBalance(current);

            if (block.timestamp < currentMaturity) {
                _establish(mode, 0 < repoTokenBalance);
            }

            current = _repoTokenList.nodes[current].next;
        }
    }

    /**
     * Configure the model of the RepoServicer for every token in the list to
     * follow the assumption that redeemTermRepoTokens will not revert.
     */
    function _guaranteeRedeemAlwaysSucceeds() internal {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            (, , address repoServicer, ) = ITermRepoToken(current).config();
            TermRepoServicer(repoServicer).guaranteeRedeemAlwaysSucceeds();

            current = _repoTokenList.nodes[current].next;
        }
    }
}
