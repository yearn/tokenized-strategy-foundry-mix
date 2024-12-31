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

contract TermAuctionListTest is KontrolTest {
    using TermAuctionList for TermAuctionListData;
    using RepoTokenList for RepoTokenListData;

    TermAuctionListData _termAuctionList;
    address _referenceAuction;

    uint256 private _auctionListSlot;

    function _auctionListOfferSlot(
        bytes32 offerId
    ) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        uint256(offerId),
                        uint256(_auctionListSlot + 2)
                    )
                )
            );
    }

    function _setReferenceAuction() internal {
        // We will copy the code of this deployed auction contract
        // into all auctions in the list
        uint256 referenceAuctionSlot;
        assembly {
            referenceAuctionSlot := _referenceAuction.slot
            sstore(_auctionListSlot.slot, _termAuctionList.slot)
        }
        _storeUInt256(
            address(this),
            referenceAuctionSlot,
            uint256(uint160(address(new TermAuction())))
        );
    }

    /**
     * Set pending offer using slot manipulation directly
     */
    function _setPendingOffer(
        bytes32 offerId,
        address repoToken,
        uint256 offerAmount,
        address auction,
        address offerLocker
    ) internal {
        uint256 offerSlot = _auctionListOfferSlot(offerId);
        _storeUInt256(address(this), offerSlot, uint256(uint160(repoToken)));
        _storeUInt256(address(this), offerSlot + 1, offerAmount);
        _storeUInt256(address(this), offerSlot + 2, uint256(uint160(auction)));
        _storeUInt256(
            address(this),
            offerSlot + 3,
            uint256(uint160(offerLocker))
        );
    }

    /**
     * Return the auction for a given offer in the list.
     */
    function _getAuction(bytes32 offerId) internal view returns (address) {
        return address(_termAuctionList.offers[offerId].termAuction);
    }

    /**
     * Deploy & initialize RepoToken and OfferLocker with the same RepoServicer
     */
    function newRepoTokenAndOfferLocker()
        public
        returns (RepoToken repoToken, TermAuctionOfferLocker offerLocker)
    {
        repoToken = new RepoToken();
        repoToken.initializeSymbolic();
        (, , address termRepoServicer, ) = repoToken.config();

        offerLocker = new TermAuctionOfferLocker();
        offerLocker.initializeSymbolic(termRepoServicer);
    }

    /**
     * Etch the code at a given address to a given address in an external call,
     * reducing memory consumption in the caller function
     */
    function etch(address dest, address src) public {
        vm.etch(dest, src.code);
    }

    function _initializeTermAuctionListEmpty() internal {
        _termAuctionList.head = TermAuctionList.NULL_NODE;
    }

    /**
     * Initialize _termAuctionList to a TermAuctionList of arbitrary size,
     * comprised of offers with distinct ids.
     */
    function _initializeTermAuctionList() internal {
        bytes32 previous = TermAuctionList.NULL_NODE;
        uint256 count = 0;
        address auction;
        RepoToken repoToken;
        TermAuctionOfferLocker offerLocker;

        while (kevm.freshBool() != 0) {
            // Create a new auction
            if (count == 0 || kevm.freshBool() != 0) {
                // Create sequential addresses to ensure that list is sorted
                auction = address(uint160(1000 + 2 * count));
                // Etch the code of the auction contract into this address
                this.etch(auction, _referenceAuction);

                TermAuction(auction).initializeSymbolic();
                (repoToken, offerLocker) = this.newRepoTokenAndOfferLocker();
            }
            // Else the aution is the same as the previous one on the list

            // Assign each offer an ID based on Strategy._generateOfferId()
            bytes32 current = keccak256(
                abi.encodePacked(count, address(this), address(offerLocker))
            );
            // Register offer in offer locker
            offerLocker.initializeSymbolicLockedOfferFor(current);

            if (previous == TermAuctionList.NULL_NODE) {
                _termAuctionList.head = current;
            } else {
                _termAuctionList.nodes[previous].next = current;
            }

            // Build PendingOffer
            _setPendingOffer(
                current,
                address(repoToken),
                freshUInt256(),
                auction,
                address(offerLocker)
            );

            previous = current;
            ++count;
        }

        if (previous == TermAuctionList.NULL_NODE) {
            _termAuctionList.head = TermAuctionList.NULL_NODE;
        } else {
            _termAuctionList.nodes[previous].next = TermAuctionList.NULL_NODE;
        }
    }

    /**
     * Initialize the TermDiscountRateAdapter to a symbolic state, ensuring that
     * it has a symbolic discount rate for every token in the PendingOffers.
     */
    function _initializeDiscountRateAdapterOffers(
        TermDiscountRateAdapter discountRateAdapter
    ) internal {
        discountRateAdapter.initializeSymbolic();

        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            discountRateAdapter.initializeSymbolicParamsFor(repoToken);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no completed auctions in the list.
     */
    function _establishNoCompletedAuctions(Mode mode) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            _establish(mode, !offer.termAuction.auctionCompleted());

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that all auctions in the list are completed.
     */
    function _establishCompletedAuctions(Mode mode) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            _establish(mode, offer.termAuction.auctionCompleted());

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * There are no matured tokens in the offers list
     */
    function _assumeNonMaturedRepoTokens() internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            (uint256 currentMaturity, , , ) = ITermRepoToken(
                _termAuctionList.offers[current].repoToken
            ).config();
            vm.assume(currentMaturity > block.timestamp);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that the offer amounts in the offer locker for completed auctions is 0
     * and for non-completed auctions is greater than 0
     */
    function _assumeOfferAmountLocked() internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = TermAuctionOfferLocker(
                address(offer.offerLocker)
            ).lockedOfferAmount(current);
            if (offer.termAuction.auctionCompleted()) {
                vm.assume(offerAmount == 0);
            } else {
                vm.assume(offerAmount > 0);
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _assumeRedemptionValueAndBalancePositive() internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            uint256 redemptionValue = ITermRepoToken(repoToken)
                .redemptionValue();
            uint256 repoTokenBalance = ITermRepoToken(repoToken).balanceOf(
                address(this)
            );
            vm.assume(0 < redemptionValue);
            vm.assume(0 < repoTokenBalance);

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _filterCompletedAuctionsGetCumulativeOfferData()
        internal
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount
        )
    {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = TermAuctionOfferLocker(
                address(offer.offerLocker)
            ).lockedOfferAmount(current);
            if (!offer.termAuction.auctionCompleted()) {
                cumulativeWeightedTimeToMaturity += RepoTokenList
                    .getRepoTokenWeightedTimeToMaturity(
                        offer.repoToken,
                        offerAmount
                    );
                cumulativeOfferAmount += offerAmount;

                // Update the list to remove the current node
                delete _termAuctionList.nodes[current];
                delete _termAuctionList.offers[current];
                if (current == _termAuctionList.head) {
                    _termAuctionList.head = next;
                } else {
                    _termAuctionList.nodes[prev].next = next;
                    current = prev;
                }
            }
            prev = current;
            current = next;
        }
    }

    function _filterRepeatedAuctions() internal {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;
        address prevAuction = address(0);

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            address offerAuction = address(
                _termAuctionList.offers[current].termAuction
            );
            if (offerAuction == prevAuction) {
                // Update the list to remove the current node
                delete _termAuctionList.nodes[current];
                delete _termAuctionList.offers[current];
                if (current == _termAuctionList.head) {
                    _termAuctionList.head = next;
                } else {
                    _termAuctionList.nodes[prev].next = next;
                    current = prev;
                }
            }
            prevAuction = offerAuction;
            prev = current;
            current = next;
        }
    }

    function _getCumulativeOfferTimeAndAmount(
        address repoToken,
        uint256 newOfferAmount
    )
        internal
        view
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        )
    {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount;

            if (offer.repoToken == repoToken) {
                offerAmount = newOfferAmount;
                found = true;
            } else {
                offerAmount = offer.offerLocker.lockedOffer(current).amount;
            }

            cumulativeWeightedTimeToMaturity += RepoTokenList
                .getRepoTokenWeightedTimeToMaturity(
                    offer.repoToken,
                    offerAmount
                );
            cumulativeOfferAmount += offerAmount;

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _getCumulativeOfferDataCompletedAuctions(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    )
        internal
        view
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount
        )
    {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = RepoTokenUtils.getNormalizedRepoTokenAmount(
                offer.repoToken,
                ITermRepoToken(offer.repoToken).balanceOf(address(this)),
                purchaseTokenPrecision,
                discountRateAdapter.repoRedemptionHaircut(offer.repoToken)
            );
            if (offerAmount > 0) {
                cumulativeWeightedTimeToMaturity += RepoTokenList
                    .getRepoTokenWeightedTimeToMaturity(
                        offer.repoToken,
                        offerAmount
                    );
                cumulativeOfferAmount += offerAmount;
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _getGroupedOfferTimeAndAmount(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    )
        internal
        view
        returns (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount
        )
    {
        bytes32 current = _termAuctionList.head;

        address previous = address(0);

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount;

            if (address(offer.termAuction) != previous) {
                offerAmount = RepoTokenUtils.getNormalizedRepoTokenAmount(
                    offer.repoToken,
                    ITermRepoToken(offer.repoToken).balanceOf(address(this)),
                    purchaseTokenPrecision,
                    discountRateAdapter.repoRedemptionHaircut(offer.repoToken)
                );
                if (offerAmount > 0) {
                    cumulativeWeightedTimeToMaturity += RepoTokenList
                        .getRepoTokenWeightedTimeToMaturity(
                            offer.repoToken,
                            offerAmount
                        );
                    cumulativeOfferAmount += offerAmount;
                }
            }

            previous = address(offer.termAuction);
            current = _termAuctionList.nodes[current].next;
        }
    }

    function _filterCompletedAuctionsGetTotalValue()
        internal
        returns (uint256 totalValue)
    {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            PendingOffer storage offer = _termAuctionList.offers[current];

            if (!offer.termAuction.auctionCompleted()) {
                totalValue += TermAuctionOfferLocker(address(offer.offerLocker))
                    .lockedOfferAmount(current);

                // Update the list to remove the current node
                delete _termAuctionList.nodes[current];
                delete _termAuctionList.offers[current];
                if (current == _termAuctionList.head) {
                    _termAuctionList.head = next;
                } else {
                    _termAuctionList.nodes[prev].next = next;
                    current = prev;
                }
            }
            prev = current;
            current = next;
        }
    }

    function _getTotalValueCompletedAuctions(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 totalValue) {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
                .getNormalizedRepoTokenAmount(
                    offer.repoToken,
                    ITermRepoToken(offer.repoToken).balanceOf(address(this)),
                    purchaseTokenPrecision,
                    discountRateAdapter.repoRedemptionHaircut(offer.repoToken)
                );
            totalValue += RepoTokenUtils.calculatePresentValue(
                repoTokenAmountInBaseAssetPrecision,
                purchaseTokenPrecision,
                RepoTokenList.getRepoTokenMaturity(offer.repoToken),
                discountRateAdapter.getDiscountRate(offer.repoToken)
            );

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that the offers in the list are sorted by auction.
     */
    function _establishSortedByAuctionId(Mode mode) internal view {
        bytes32 previous = TermAuctionList.NULL_NODE;
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            if (previous != TermAuctionList.NULL_NODE) {
                address previousAuction = _getAuction(previous);
                address currentAuction = _getAuction(current);
                _establish(mode, previousAuction <= currentAuction);
            }

            previous = current;
            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no duplicate offers in the list.
     */
    function _establishNoDuplicateOffers(Mode mode) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 other = _termAuctionList.nodes[current].next;

            while (other != TermAuctionList.NULL_NODE) {
                _establish(mode, current != other);
                other = _termAuctionList.nodes[other].next;
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that there are no completed auctions in the list.
     */
    function _establishNoCompletedOrCancelledAuctions(Mode mode) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            _establish(mode, !offer.termAuction.auctionCompleted());
            _establish(
                mode,
                !offer.termAuction.auctionCancelledForWithdrawal()
            );

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that all offer amounts are > 0.
     */
    function _establishPositiveOfferAmounts(Mode mode) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            _establish(mode, 0 < offer.offerAmount);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that the offer amounts recorded in the list are the same
     * as the offer amounts in the offer locker.
     */
    function _establishOfferAmountMatchesAmountLocked(
        Mode mode,
        bytes32 offerId
    ) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            if (offerId == 0 || offerId != current) {
                PendingOffer storage offer = _termAuctionList.offers[current];
                uint256 offerAmount = TermAuctionOfferLocker(
                    address(offer.offerLocker)
                ).lockedOfferAmount(current);
                _establish(mode, offer.offerAmount == offerAmount);
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Count the number of offers in the list.
     *
     * Note that this function guarantees the following postconditions:
     * - The head of the list is NULL_NODE iff the count is 0.
     * - If the count is N, the Nth node in the list is followed by NULL_NODE.
     */
    function _countOffersInList() internal view returns (uint256) {
        uint256 count = 0;
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            ++count;
            current = _termAuctionList.nodes[current].next;
        }

        return count;
    }

    /**
     * Return true if the given offer id is in the list, and false otherwise.
     */
    function _offerInList(bytes32 offerId) internal view returns (bool) {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            if (current == offerId) {
                return true;
            }

            current = _termAuctionList.nodes[current].next;
        }

        return false;
    }

    /**
     * Assume that the address doesn't overlap with any preexisting addresses.
     * This is necessary in order to use cheatcodes on a symbolic address that
     * change its code or storage.
     */
    function _assumeNewAddress(address freshAddress) internal view {
        vm.assume(10 <= uint160(freshAddress));

        vm.assume(freshAddress != address(this));
        vm.assume(freshAddress != address(vm));
        vm.assume(freshAddress != address(kevm));

        vm.assume(freshAddress != address(_referenceAuction));

        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            (
                ,
                ,
                address termRepoServicer,
                address termRepoCollateralManager
            ) = ITermRepoToken(offer.repoToken).config();

            vm.assume(freshAddress != offer.repoToken);
            vm.assume(freshAddress != address(offer.termAuction));
            vm.assume(freshAddress != address(offer.offerLocker));
            vm.assume(freshAddress != termRepoServicer);
            vm.assume(freshAddress != termRepoCollateralManager);

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _termAuctionListToArray(
        uint256 length
    ) internal view returns (bytes32[] memory offerIds) {
        bytes32 current = _termAuctionList.head;
        uint256 i;
        offerIds = new bytes32[](length);

        while (current != TermAuctionList.NULL_NODE) {
            offerIds[i++] = current;
            current = _termAuctionList.nodes[current].next;
        }
    }

    function _establishInsertListPreservation(
        bytes32 newOfferId,
        bytes32[] memory offerIds,
        uint256 offerIdsCount
    ) internal view {
        bytes32 current = _termAuctionList.head;
        uint256 i = 0;

        if (newOfferId != bytes32(0)) {
            while (current != TermAuctionList.NULL_NODE && i < offerIdsCount) {
                if (current != offerIds[i]) {
                    assert(current == newOfferId);
                    current = _termAuctionList.nodes[current].next;
                    break;
                }
                i++;
                current = _termAuctionList.nodes[current].next;
            }

            if (current != TermAuctionList.NULL_NODE && i == offerIdsCount) {
                assert(current == newOfferId);
            }
        }

        while (current != TermAuctionList.NULL_NODE && i < offerIdsCount) {
            assert(current == offerIds[i++]);
            current = _termAuctionList.nodes[current].next;
        }
    }

    function _establishRemoveListPreservation(
        bytes32[] memory offerIds,
        uint256 offerIdsCount
    ) internal view {
        bytes32 current = _termAuctionList.head;
        uint256 i = 0;

        while (current != TermAuctionList.NULL_NODE && i < offerIdsCount) {
            if (current == offerIds[i++]) {
                current = _termAuctionList.nodes[current].next;
            }
        }

        assert(current == TermAuctionList.NULL_NODE);
    }

    /**
     * Configure the model of the OfferLocker for every offer in the list to
     * follow the assumption that unlockOffers will not revert.
     */
    function _guaranteeUnlockAlwaysSucceeds() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            TermAuctionOfferLocker offerLocker = TermAuctionOfferLocker(
                address(offer.offerLocker)
            );

            offerLocker.guaranteeUnlockAlwaysSucceeds();

            current = _termAuctionList.nodes[current].next;
        }
    }
}
