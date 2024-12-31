pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";
import "src/TermAuctionList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/RepoTokenListInvariants.t.sol";
import "src/test/kontrol/TermAuction.sol";
import "src/test/kontrol/TermAuctionListTest.t.sol";
import "src/test/kontrol/TermAuctionOfferLocker.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract TermAuctionListInvariantsTest is
    RepoTokenListTest,
    TermAuctionListTest
{
    using TermAuctionList for TermAuctionListData;
    using RepoTokenList for RepoTokenListData;

    function setUp() public {
        // Make storage of this contract completely symbolic
        kevm.symbolicStorage(address(this));

        _setReferenceAuction();

        // Initialize TermAuctionList of arbitrary size
        _initializeTermAuctionList();
    }

    /**
     * Test that insertPending preserves the list invariants when a new offer
     * is added (that was not present in the list before).
     */
    function testInsertPendingNewOffer(
        bytes32 offerId,
        address asset
    ) external {
        // offerId must not equal zero, otherwise the linked list breaks
        vm.assume(offerId != TermAuctionList.NULL_NODE);

        // Our initialization procedure guarantees these invariants,
        // so we assert instead of assuming
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);

        // Assume that the invariants hold before the function is called
        _establishOfferAmountMatchesAmountLocked(Mode.Assume, bytes32(0));
        _establishNoCompletedOrCancelledAuctions(Mode.Assume);
        _establishPositiveOfferAmounts(Mode.Assume);
        _assumeRepoTokensValidate(asset, true);

        // Save the number of offers in the list before the function is called
        uint256 count = _countOffersInList();
        bytes32[] memory offers = _termAuctionListToArray(count);

        // Assume that the auction is a fresh address that doesn't overlap with
        // any others, then initialize it to contain TermAuction code
        //
        // NOTE: The auction address needs to remain symbolic, otherwise its
        // place in the list will be predetermined and the test won't be general
        address auction = freshAddress();
        _assumeNewAddress(auction);

        // Initialize RepoToken and OfferLocker, making sure that the addresses
        // also don't overlap with the symbolic auction
        (RepoToken repoToken, TermAuctionOfferLocker offerLocker) = this
            .newRepoTokenAndOfferLocker();
        offerLocker.initializeSymbolicLockedOfferFor(offerId);
        (
            ,
            ,
            address termRepoServicer,
            address termRepoCollateralManager
        ) = repoToken.config();
        _assumeRepoTokenValidate(address(repoToken), asset, true);
        vm.assume(
            0 < TermAuctionOfferLocker(offerLocker).lockedOfferAmount(offerId)
        );
        vm.assume(auction != address(repoToken));
        vm.assume(auction != address(offerLocker));
        vm.assume(auction != termRepoServicer);
        vm.assume(auction != termRepoCollateralManager);
        vm.assume(auction != asset);

        // Now we can etch the auction in, when all other addresses have been created
        this.etch(auction, _referenceAuction);
        TermAuction(auction).initializeSymbolic();
        vm.assume(!TermAuction(auction).auctionCompleted());
        vm.assume(!TermAuction(auction).auctionCancelledForWithdrawal());

        // Build new PendingOffer
        PendingOffer memory pendingOffer;
        pendingOffer.repoToken = address(repoToken);
        pendingOffer.offerAmount = TermAuctionOfferLocker(offerLocker)
            .lockedOfferAmount(offerId);
        pendingOffer.termAuction = ITermAuction(auction);
        pendingOffer.offerLocker = ITermAuctionOfferLocker(offerLocker);

        // Assume that the offer is not already in the list
        vm.assume(!_offerInList(offerId));

        // Call the function being tested
        _termAuctionList.insertPending(offerId, pendingOffer);

        // Assert that the size of the list increased by 1
        // NOTE: This assertion breaks if offerId equals zero
        assert(_countOffersInList() == count + 1);

        // Assert that the new offer is in the list
        //assert(_offerInList(offerId));
        _establishInsertListPreservation(offerId, offers, count);

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishNoCompletedOrCancelledAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert, bytes32(0));
        _assertRepoTokensValidate(asset);
    }

    /**
     * Test that insertPending preserves the list invariants when trying to
     * insert an offer that is already in the list.
     */
    function testInsertPendingDuplicateOffer(
        bytes32 offerId,
        PendingOffer memory pendingOffer,
        address asset
    ) external {
        // offerId must not equal zero, otherwise the linked list breaks
        // TODO: Does the code protect against this?
        vm.assume(offerId != TermAuctionList.NULL_NODE);

        // Save the number of offers in the list before the function is called
        uint256 count = _countOffersInList();
        bytes32[] memory offers = _termAuctionListToArray(count);

        // Assume that the offer is already in the list
        vm.assume(_offerInList(offerId));

        // Our initialization procedure guarantees these invariants,
        // so we assert instead of assuming
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);

        // Assume that the invariants hold before the function is called
        _establishOfferAmountMatchesAmountLocked(Mode.Assume, offerId);
        _establishNoCompletedOrCancelledAuctions(Mode.Assume);
        _establishPositiveOfferAmounts(Mode.Assume);
        _assumeRepoTokensValidate(asset, true);

        PendingOffer memory offer = _termAuctionList.offers[offerId];
        // Calls to the Strategy.submitAuctionOffer need to ensure that the following 2 assumptions hold before the call
        vm.assume(offer.termAuction == pendingOffer.termAuction);
        vm.assume(offer.repoToken == address(pendingOffer.repoToken));
        // This is ensured by the _validateAndGetOfferLocker if the above assumptions hold
        vm.assume(offer.offerLocker == pendingOffer.offerLocker);
        // This is being checked by Strategy.submitAuctionOffer
        vm.assume(pendingOffer.offerAmount > 0);
        vm.assume(
            pendingOffer.offerAmount ==
                TermAuctionOfferLocker(address(pendingOffer.offerLocker))
                    .lockedOfferAmount(offerId)
        );

        // Call the function being tested
        _termAuctionList.insertPending(offerId, pendingOffer);

        // Assert that the size of the list didn't change
        assert(_countOffersInList() == count);

        // Assert that the new offer is in the list
        //assert(_offerInList(offerId));
        _establishInsertListPreservation(bytes32(0), offers, count);

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishNoCompletedOrCancelledAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert, bytes32(0));
        _assertRepoTokensValidate(asset);
    }

    /**
     * Assume that all RepoTokens in the PendingOffers have no discount rate
     * set in the RepoTokenList.
     */
    function _assumeNoDiscountRatesSet() internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            uint256 discountRate = _repoTokenList.discountRates[repoToken];
            vm.assume(discountRate == RepoTokenList.INVALID_AUCTION_RATE);

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _assumeRepoTokenValidate(
        address repoToken,
        address asset,
        bool assumeTimestamp
    ) internal view {
        (
            uint256 redemptionTimestamp,
            address purchaseToken,
            ,
            address collateralManager
        ) = ITermRepoToken(repoToken).config();

        vm.assume(purchaseToken == asset);
        if (assumeTimestamp) {
            vm.assume(block.timestamp <= redemptionTimestamp);
        }

        uint256 numTokens = ITermRepoCollateralManager(collateralManager)
            .numOfAcceptedCollateralTokens();

        for (uint256 i; i < numTokens; i++) {
            address currentToken = ITermRepoCollateralManager(collateralManager)
                .collateralTokens(i);
            uint256 minCollateralRatio = _repoTokenList.collateralTokenParams[
                currentToken
            ];

            vm.assume(minCollateralRatio != 0);
            vm.assume(
                ITermRepoCollateralManager(collateralManager)
                    .maintenanceCollateralRatios(currentToken) >=
                    minCollateralRatio
            );
        }
    }

    function _assumeRepoTokensValidate(
        address asset,
        bool assumeTimestamp
    ) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            if (assumeTimestamp) {
                _assumeRepoTokenValidate(repoToken, asset, true);
            } else {
                bool auctionCompleted = _termAuctionList
                    .offers[current]
                    .termAuction
                    .auctionCompleted();
                _assumeRepoTokenValidate(repoToken, asset, !auctionCompleted);
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _assertRepoTokensValidate(address asset) internal view {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            (bool isRepoTokenValid, ) = _repoTokenList.validateRepoToken(
                ITermRepoToken(repoToken),
                asset
            );
            assert(isRepoTokenValid);

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _guaranteeRedeemOfferRepoTokenAlwaysSucceeds() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            (, , address repoServicer, ) = ITermRepoToken(repoToken).config();
            TermRepoServicer(repoServicer).guaranteeRedeemAlwaysSucceeds();

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Test that removeCompleted preserves the list invariants.
     */
    function testRemoveCompleted(address asset) external {
        // For simplicity, assume that the RepoTokenList is empty
        _repoTokenList.head = RepoTokenList.NULL_NODE;
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
        _initializeDiscountRateAdapterOffers(discountRateAdapter);

        // Our initialization procedure guarantees these invariants,
        // so we assert instead of assuming
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);

        // Assume that the invariants hold before the function is called
        _establishOfferAmountMatchesAmountLocked(Mode.Assume, bytes32(0));

        // Assume that the calls to unlockOffers will not revert
        _guaranteeUnlockAlwaysSucceeds();

        // Assume that the RepoTokens in PendingOffers have no discount rate set
        _assumeNoDiscountRatesSet();

        // Assume that the RepoTokens in PendingOffers pass validation
        _assumeRepoTokensValidate(asset, false);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countOffersInList();
        bytes32[] memory offers = _termAuctionListToArray(count);

        // Call the function being tested
        _termAuctionList.removeCompleted(
            _repoTokenList,
            discountRateAdapter,
            asset
        );

        // Assert that the size of the list is less than or equal to before
        assert(_countOffersInList() <= count);

        _establishRemoveListPreservation(offers, count);

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert, bytes32(0));

        // Now the following invariants should hold as well
        _establishNoCompletedOrCancelledAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _assertRepoTokensValidate(asset);
    }

    function testGetCumulativeDataEmpty(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        _initializeTermAuctionListEmpty();

        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        ) = _termAuctionList.getCumulativeOfferData(
                _repoTokenList,
                ITermDiscountRateAdapter(address(discountRateAdapter)),
                repoToken,
                newOfferAmount,
                purchaseTokenPrecision
            );

        assert(cumulativeWeightedTimeToMaturity == 0);
        assert(cumulativeOfferAmount == 0);
        assert(found == false);
    }

    function testGetPresentValueEmpty(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        _initializeTermAuctionListEmpty();

        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();

        uint256 totalPresentValue = _termAuctionList.getPresentValue(
            _repoTokenList,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        assert(totalPresentValue == 0);
    }

    /* If there are no completed auctions in the list then getCumulativeOfferData should return the sum 
       of the amount in the lockedOffer for all offers
    */
    function testGetCumulativeDataNoCompletedAuctions(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
        _initializeDiscountRateAdapterOffers(discountRateAdapter);

        _establishNoCompletedAuctions(Mode.Assume);
        _assumeOfferAmountLocked();

        vm.assume(newOfferAmount < ETH_UPPER_BOUND);
        vm.assume(purchaseTokenPrecision <= 18);

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        ) = _termAuctionList.getCumulativeOfferData(
                _repoTokenList,
                ITermDiscountRateAdapter(address(discountRateAdapter)),
                repoToken,
                newOfferAmount,
                purchaseTokenPrecision
            );

        (
            uint256 cumulativeWeightedTimeToMaturityNoCompletedAuctions,
            uint256 cumulativeOfferAmountNoCompletedAuctions,
            bool foundNoCompletedAuctions
        ) = _getCumulativeOfferTimeAndAmount(repoToken, newOfferAmount);

        assert(
            cumulativeWeightedTimeToMaturity ==
                cumulativeWeightedTimeToMaturityNoCompletedAuctions
        );
        assert(
            cumulativeOfferAmount == cumulativeOfferAmountNoCompletedAuctions
        );
        assert(found == foundNoCompletedAuctions);
    }

    /* If there are no completed auctions in the list then getCumulativeOfferData should return the sum 
       of the amount in the lockedOffer for all offers
    */
    function testGetCumulativeDataCompletedAuctions(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
        _initializeDiscountRateAdapterOffers(discountRateAdapter);

        _establishCompletedAuctions(Mode.Assume);
        _assumeOfferAmountLocked();
        _assumeNoDiscountRatesSet();
        _assumeRedemptionValueAndBalancePositive();

        // Consider only the case where we are not trying to match a token
        vm.assume(repoToken == address(0));
        vm.assume(newOfferAmount < ETH_UPPER_BOUND);
        vm.assume(purchaseTokenPrecision <= 18);
        vm.assume(purchaseTokenPrecision > 0);

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        ) = _termAuctionList.getCumulativeOfferData(
                _repoTokenList,
                ITermDiscountRateAdapter(address(discountRateAdapter)),
                repoToken,
                newOfferAmount,
                purchaseTokenPrecision
            );

        (
            uint256 cumulativeWeightedTimeToMaturityCompletedAuctions,
            uint256 cumulativeOfferAmountCompletedAuctions
        ) = _getGroupedOfferTimeAndAmount(
                ITermDiscountRateAdapter(address(discountRateAdapter)),
                purchaseTokenPrecision
            );

        assert(
            cumulativeWeightedTimeToMaturity ==
                cumulativeWeightedTimeToMaturityCompletedAuctions
        );
        assert(cumulativeOfferAmount == cumulativeOfferAmountCompletedAuctions);
    }

    function _filterDiscountRateSet() internal {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            address repoToken = _termAuctionList.offers[current].repoToken;
            uint256 discountRate = _repoTokenList.discountRates[repoToken];

            if (discountRate != RepoTokenList.INVALID_AUCTION_RATE) {
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

    function testGetCumulativeOfferData(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
        _initializeDiscountRateAdapterOffers(discountRateAdapter);

        _assumeNonMaturedRepoTokens();
        _assumeOfferAmountLocked();
        _assumeRedemptionValueAndBalancePositive();

        // Consider only the case where we are not trying to match a token
        vm.assume(repoToken == address(0));
        vm.assume(newOfferAmount < ETH_UPPER_BOUND);
        vm.assume(purchaseTokenPrecision <= 18);
        vm.assume(purchaseTokenPrecision > 0);

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool found
        ) = _termAuctionList.getCumulativeOfferData(
                _repoTokenList,
                ITermDiscountRateAdapter(address(discountRateAdapter)),
                repoToken,
                newOfferAmount,
                purchaseTokenPrecision
            );

        assert(!found);

        (
            uint256 cumulativeWeightedTimeToMaturityIncompletedAuctions,
            uint256 cumulativeOfferAmountIncompletedAuctions
        ) = _filterCompletedAuctionsGetCumulativeOfferData();

        _filterDiscountRateSet();
        _filterRepeatedAuctions();

        (
            uint256 cumulativeWeightedTimeToMaturityCompletedAuctions,
            uint256 cumulativeOfferAmountCompletedAuctions
        ) = _getCumulativeOfferDataCompletedAuctions(
                discountRateAdapter,
                purchaseTokenPrecision
            );

        assert(
            cumulativeWeightedTimeToMaturity ==
                cumulativeWeightedTimeToMaturityIncompletedAuctions +
                    cumulativeWeightedTimeToMaturityCompletedAuctions
        );
        assert(
            cumulativeOfferAmount ==
                cumulativeOfferAmountIncompletedAuctions +
                    cumulativeOfferAmountCompletedAuctions
        );
    }

    function testGetPresentTotalValue(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
        _initializeDiscountRateAdapterOffers(discountRateAdapter);

        _assumeOfferAmountLocked();

        // Consider only the case where we are not trying to match a token
        vm.assume(repoTokenToMatch == address(0));
        vm.assume(purchaseTokenPrecision <= 18);
        vm.assume(purchaseTokenPrecision > 0);

        uint256 totalPresentValue = _termAuctionList.getPresentValue(
            _repoTokenList,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        uint256 totalValueNonCompletedAuctions = _filterCompletedAuctionsGetTotalValue();

        _filterDiscountRateSet();
        _filterRepeatedAuctions();

        uint256 totalValueCompletedAuctions = _getTotalValueCompletedAuctions(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision
        );

        assert(
            totalPresentValue ==
                totalValueNonCompletedAuctions + totalValueCompletedAuctions
        );
    }
}
