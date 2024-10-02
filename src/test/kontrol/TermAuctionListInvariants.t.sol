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
import "src/test/kontrol/TermAuctionOfferLocker.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract TermAuctionListInvariantsTest is RepoTokenListInvariantsTest {
    using TermAuctionList for TermAuctionListData;

    TermAuctionListData _termAuctionList;
    address _referenceAuction;

    function setUp() public {
        // Make storage of this contract completely symbolic
        kevm.symbolicStorage(address(this));

        // We will copy the code of this deployed auction contract into all
        // auctions in the list
        _referenceAuction = address(new TermAuction());

        // Initialize TermAuctionList of arbitrary size
        _initializeTermAuctionList();
    }

    /**
     * Return the auction for a given offer in the list.
     */
    function _getAuction(bytes32 offerId) internal returns(address) {
        return address(_termAuctionList.offers[offerId].termAuction);
    }

    /**
     * Deploy & initialize RepoToken and OfferLocker with the same RepoServicer
     */
    function newRepoTokenAndOfferLocker() public returns (
        RepoToken repoToken,
        TermAuctionOfferLocker offerLocker
    ) {
        repoToken = new RepoToken();
        repoToken.initializeSymbolic();
        (, , address termRepoServicer,) = repoToken.config();

        offerLocker = new TermAuctionOfferLocker();
        offerLocker.initializeSymbolic(termRepoServicer);
    }

    /**
     * Initialize _termAuctionList to a TermAuctionList of arbitrary size,
     * comprised of offers with distinct ids.
     */
    function _initializeTermAuctionList() internal {
        bytes32 previous = TermAuctionList.NULL_NODE;
        uint256 count = 0;

        while (kevm.freshBool() != 0) {
            (RepoToken repoToken, TermAuctionOfferLocker offerLocker) =
                this.newRepoTokenAndOfferLocker();

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

            // Create sequential addresses to ensure that list is sorted
            address auction = address(uint160(1000 + count));
            // Etch the code of the auction contract into this address
            this.etch(auction, _referenceAuction);
            TermAuction(auction).initializeSymbolic();

            // Build PendingOffer
            PendingOffer storage offer = _termAuctionList.offers[current];
            offer.repoToken = address(repoToken);
            offer.offerAmount = freshUInt256();
            offer.termAuction = ITermAuction(auction);
            offer.offerLocker = offerLocker;

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
    function _initializeDiscountRateAdapter(
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
     * Assume or assert that the offers in the list are sorted by auction.
     */
    function _establishSortedByAuctionId(Mode mode) internal {
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
    function _establishNoDuplicateOffers(Mode mode) internal {
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
    function _establishNoCompletedAuctions(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            _establish(mode, !offer.termAuction.auctionCompleted());

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that all offer amounts are > 0.
     */
    function _establishPositiveOfferAmounts(Mode mode) internal {
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
    function _establishOfferAmountMatchesAmountLocked(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = offer.offerLocker.lockedOfferAmount(current);
            _establish(mode, offer.offerAmount == offerAmount);

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
    function _countOffersInList() internal returns (uint256) {
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
    function _offerInList(bytes32 offerId) internal returns (bool) {
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
    function _assumeNewAddress(address freshAddress) internal {
        vm.assume(10 <= uint160(freshAddress));

        vm.assume(freshAddress != address(this));
        vm.assume(freshAddress != address(vm));
        vm.assume(freshAddress != address(kevm));

        vm.assume(freshAddress != address(_referenceAuction));

        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            (,, address termRepoServicer, address termRepoCollateralManager) =
                ITermRepoToken(offer.repoToken).config();

            vm.assume(freshAddress != offer.repoToken);
            vm.assume(freshAddress != address(offer.termAuction));
            vm.assume(freshAddress != address(offer.offerLocker));
            vm.assume(freshAddress != termRepoServicer);
            vm.assume(freshAddress != termRepoCollateralManager);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Etch the code at a given address to a given address in an external call,
     * reducing memory consumption in the caller function
     */
    function etch(address dest, address src) public {
      vm.etch(dest, src.code);
    }

    /**
     * Test that insertPending preserves the list invariants when a new offer
     * is added (that was not present in the list before).
     */
    function testInsertPendingNewOffer(
        bytes32 offerId
    ) external {
        // offerId must not equal zero, otherwise the linked list breaks
        // TODO: Does the code protect against this?
        vm.assume(offerId != TermAuctionList.NULL_NODE);

        // Our initialization procedure guarantees these invariants,
        // so we assert instead of assuming
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);

        // Assume that the invariants hold before the function is called
        _establishOfferAmountMatchesAmountLocked(Mode.Assume);
        _establishNoCompletedAuctions(Mode.Assume);
        _establishPositiveOfferAmounts(Mode.Assume);

        // Save the number of offers in the list before the function is called
        uint256 count = _countOffersInList();

        // Assume that the auction is a fresh address that doesn't overlap with
        // any others, then initialize it to contain TermAuction code
        //
        // NOTE: The auction address needs to remain symbolic, otherwise its
        // place in the list will be predetermined and the test won't be general
        address auction = freshAddress();
        _assumeNewAddress(auction);

        // Initialize RepoToken and OfferLocker, making sure that the addresses
        // also don't overlap with the symbolic auction
        (RepoToken repoToken, TermAuctionOfferLocker offerLocker) =
            this.newRepoTokenAndOfferLocker();
        offerLocker.initializeSymbolicLockedOfferFor(offerId);
        (,, address termRepoServicer, address termRepoCollateralManager) =
            repoToken.config();
        vm.assume(0 < offerLocker.lockedOfferAmount(offerId));
        vm.assume(auction != address(repoToken));
        vm.assume(auction != address(offerLocker));
        vm.assume(auction != termRepoServicer);
        vm.assume(auction != termRepoCollateralManager);

        // Now we can etch the auction in, when all other addresses have been created
        this.etch(auction, _referenceAuction);
        TermAuction(auction).initializeSymbolic();
        vm.assume(!TermAuction(auction).auctionCompleted());

        // Build new PendingOffer
        PendingOffer memory pendingOffer;
        pendingOffer.repoToken = address(repoToken);
        pendingOffer.offerAmount = offerLocker.lockedOfferAmount(offerId);
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
        assert(_offerInList(offerId));

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishNoCompletedAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert);
    }


    /**
     * Test that insertPending preserves the list invariants when trying to
     * insert an offer that is already in the list.
     */
    function testInsertPendingDuplicateOffer(
        bytes32 offerId,
        PendingOffer memory pendingOffer
    ) external {
        // offerId must not equal zero, otherwise the linked list breaks
        // TODO: Does the code protect against this?
        vm.assume(offerId != TermAuctionList.NULL_NODE);

        // Our initialization procedure guarantees these invariants,
        // so we assert instead of assuming
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);

        // Assume that the invariants hold before the function is called
        _establishOfferAmountMatchesAmountLocked(Mode.Assume);
        _establishNoCompletedAuctions(Mode.Assume);
        _establishPositiveOfferAmounts(Mode.Assume);

        // Save the number of offers in the list before the function is called
        uint256 count = _countOffersInList();

        // Assume that the offer is already in the list
        vm.assume(_offerInList(offerId));
        vm.assume(0 < pendingOffer.offerAmount);
        vm.assume(_getAuction(offerId) == address(pendingOffer.termAuction));
        vm.assume(_termAuctionList.offers[offerId].offerLocker == pendingOffer.offerLocker);

        // Call the function being tested
        _termAuctionList.insertPending(offerId, pendingOffer);

        // Assert that the size of the list didn't change
        assert(_countOffersInList() == count);

        // Assert that the new offer is in the list
        assert(_offerInList(offerId));

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishNoCompletedAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert);
    }

    /**
     * Configure the model of the OfferLocker for every offer in the list to
     * follow the assumption that unlockOffers will not revert.
     */
    function _guaranteeUnlockAlwaysSucceeds() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            TermAuctionOfferLocker offerLocker =
                TermAuctionOfferLocker(address(offer.offerLocker));

            offerLocker.guaranteeUnlockAlwaysSucceeds();

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume that all RepoTokens in the PendingOffers have no discount rate
     * set in the RepoTokenList.
     */
    function _assumeNoDiscountRatesSet() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            uint256 discountRate = _repoTokenList.discountRates[repoToken];
            vm.assume(discountRate == RepoTokenList.INVALID_AUCTION_RATE);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume that all RepoTokens in the PendingOffers pass the checks performed
     * in validateRepoToken, to ensure the function won't revert if they need to
     * be inserted in the RepoTokenList.
     */
    function _assumeRepoTokensValidate(address asset) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            (
             uint256 redemptionTimestamp,
             address purchaseToken,
             ,
             address collateralManager
            ) = ITermRepoToken(repoToken).config();

            vm.assume(purchaseToken != asset);
            vm.assume(redemptionTimestamp < block.timestamp);

            uint256 numTokens = ITermRepoCollateralManager(collateralManager).numOfAcceptedCollateralTokens();

            for (uint256 i; i < numTokens; i++) {
                address currentToken = ITermRepoCollateralManager(collateralManager).collateralTokens(i);
                uint256 minCollateralRatio = freshUInt256();
                _repoTokenList.collateralTokenParams[currentToken] = minCollateralRatio;

                vm.assume(minCollateralRatio != 0);
                vm.assume(
                    ITermRepoCollateralManager(collateralManager).maintenanceCollateralRatios(currentToken) < minCollateralRatio
                );
            }

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
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        // Our initialization procedure guarantees these invariants,
        // so we assert instead of assuming
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);

        // Assume that the invariants hold before the function is called
        _establishOfferAmountMatchesAmountLocked(Mode.Assume);

        // Assume that the calls to unlockOffers will not revert
        _guaranteeUnlockAlwaysSucceeds();

        // Assume that the RepoTokens in PendingOffers have no discount rate set
        _assumeNoDiscountRatesSet();

        // Assume that the RepoTokens in PendingOffers pass validation
        _assumeRepoTokensValidate(asset);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countOffersInList();

        // Call the function being tested
        _termAuctionList.removeCompleted(
            _repoTokenList,
            discountRateAdapter,
            asset
        );

        // Assert that the size of the list is less than or equal to before
        assert(_countOffersInList() <= count);

        // Assert that the invariants are preserved
        _establishSortedByAuctionId(Mode.Assert);
        _establishNoDuplicateOffers(Mode.Assert);
        _establishOfferAmountMatchesAmountLocked(Mode.Assert);

        // Now the following invariants should hold as well
        _establishNoCompletedAuctions(Mode.Assert);
        _establishPositiveOfferAmounts(Mode.Assert);
    }
}
