pragma solidity 0.8.23;

import "src/test/kontrol/TermAuction.sol";
import "src/test/kontrol/ListTestUtils.t.sol";



contract TermAuctionListGetTest is RepoTokenListTest, TermAuctionListTest {
    using TermAuctionList for TermAuctionListData;
    using RepoTokenList for RepoTokenListData;

    function setUp() public {
        // Make storage of this contract completely symbolic
        kevm.symbolicStorage(address(this));
        // Initialize RepoTokenList of arbitrary size
        //_initializeRepoTokenList();

        setReferenceAuction();
        // Initialize TermAuctionList of arbitrary size
        _initializeTermAuctionList();
    }

    function _initializeTermAuctionListEmpty() internal {
        _termAuctionList.head = TermAuctionList.NULL_NODE;
    }

    function testGetCumulativeDataEmpty(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        _initializeTermAuctionListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

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

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        uint256 totalPresentValue = _termAuctionList.getPresentValue(
            _repoTokenList,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        assert(totalPresentValue == 0);
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
     * Assume or assert that all auctions in the list are completed.
     */
    function _establishCompletedAuctions(Mode mode) internal {
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
    function _assumeNonMaturedRepoTokens() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            (uint256 currentMaturity, , ,) = ITermRepoToken(_termAuctionList.offers[current].repoToken).config();
            vm.assume(currentMaturity > block.timestamp);

            current = _termAuctionList.nodes[current].next;
        }
    }

    /**
     * Assume or assert that the offer amounts in the offer locker for completed auctions is 0
     * and for non-completed auctions is greater than 0
     */
    function _assumeOfferAmountLocked() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = TermAuctionOfferLocker(address(offer.offerLocker)).lockedOfferAmount(current);
            if (offer.termAuction.auctionCompleted()) {
                vm.assume(offerAmount == 0);
            }
            else {
                vm.assume(offerAmount > 0);
            }
    
            current = _termAuctionList.nodes[current].next;
        }
    }


    /**
     * Assume or assert that the offer amounts in the offer locker for each offer in the list
     * is equal to 0
     */
    function _establishOfferAmountLockedZero(Mode mode) internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = TermAuctionOfferLocker(address(offer.offerLocker)).lockedOfferAmount(current);
            _establish(mode, offer.offerAmount == 0);

            current = _termAuctionList.nodes[current].next;
        }
    }

    function filterCompletedAuctionsGetCumulativeOfferData() internal returns (uint256 cumulativeWeightedTimeToMaturity, uint256 cumulativeOfferAmount) {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = TermAuctionOfferLocker(address(offer.offerLocker)).lockedOfferAmount(current);
            if (!offer.termAuction.auctionCompleted()) {
                cumulativeWeightedTimeToMaturity += RepoTokenList.getRepoTokenWeightedTimeToMaturity(offer.repoToken, offerAmount);
                cumulativeOfferAmount += offerAmount;

                // Update the list to remove the current node
                delete _termAuctionList.nodes[current];
                delete _termAuctionList.offers[current];
                if (current == _termAuctionList.head) {
                    _termAuctionList.head = next;
                }
                else {
                    _termAuctionList.nodes[prev].next = next;
                    current = prev;
                }
            }
            prev = current;
            current = next;
        }
    }


    function filterDiscountRateSet() internal {
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
                }
                else {
                    _termAuctionList.nodes[prev].next = next;
                    current = prev;
                }
            }
            prev = current;
            current = next;
        }
    }

    function filterRepeatedAuctions() internal {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;
        address prevAuction = address(0);
        
        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            address offerAuction = address(_termAuctionList.offers[current].termAuction);
            if (offerAuction == prevAuction) {
                // Update the list to remove the current node
                delete _termAuctionList.nodes[current];
                delete _termAuctionList.offers[current];
                if (current == _termAuctionList.head) {
                    _termAuctionList.head = next;
                }
                else {
                    _termAuctionList.nodes[prev].next = next;
                    current = prev;
                }
            }
            prevAuction = offerAuction;
            prev = current;
            current = next;
        }
    }


    function getCumulativeOfferTimeAndAmount(
        RepoTokenListData storage repoTokenListData,
        ITermDiscountRateAdapter discountRateAdapter,
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 cumulativeWeightedTimeToMaturity, uint256 cumulativeOfferAmount, bool found) {
        
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

            cumulativeWeightedTimeToMaturity += RepoTokenList.getRepoTokenWeightedTimeToMaturity(offer.repoToken, offerAmount);
            cumulativeOfferAmount += offerAmount;

            current = _termAuctionList.nodes[current].next;
        }
    }

    function _getCumulativeOfferDataCompletedAuctions(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 cumulativeWeightedTimeToMaturity, uint256 cumulativeOfferAmount) {
        
        bytes32 current = _termAuctionList.head;

        address previous = address(0);

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = RepoTokenUtils.getNormalizedRepoTokenAmount(
                                    offer.repoToken,
                                    ITermRepoToken(offer.repoToken).balanceOf(address(this)),
                                    purchaseTokenPrecision,
                                    discountRateAdapter.repoRedemptionHaircut(offer.repoToken)
                                );
            if (offerAmount > 0) {
                cumulativeWeightedTimeToMaturity += RepoTokenList.getRepoTokenWeightedTimeToMaturity(offer.repoToken, offerAmount);
                cumulativeOfferAmount += offerAmount;
            }

            current = _termAuctionList.nodes[current].next;
        }
    }

    function getGroupedOfferTimeAndAmount(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256 cumulativeWeightedTimeToMaturity, uint256 cumulativeOfferAmount, bool found) {
        
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
                    cumulativeWeightedTimeToMaturity += RepoTokenList.getRepoTokenWeightedTimeToMaturity(offer.repoToken, offerAmount);
                    cumulativeOfferAmount += offerAmount;
                }
            }
            
            previous = address(offer.termAuction);
            current = _termAuctionList.nodes[current].next;
        }
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
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        _establishNoCompletedAuctions(Mode.Assume);

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
        ) = getCumulativeOfferTimeAndAmount(
            _repoTokenList,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            repoToken,
            newOfferAmount,
            purchaseTokenPrecision
        );

        assert(cumulativeWeightedTimeToMaturity == cumulativeWeightedTimeToMaturityNoCompletedAuctions);
        assert(cumulativeOfferAmount == cumulativeOfferAmountNoCompletedAuctions);
        assert(found == foundNoCompletedAuctions);

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

    /* If there are no completed auctions in the list then getCumulativeOfferData should return the sum 
       of the amount in the lockedOffer for all offers
    */
    function testGetCumulativeDataCompletedAuctions(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        _establishCompletedAuctions(Mode.Assume);
        _assumeOfferAmountLocked();
        _assumeNoDiscountRatesSet();

        // Consider only the case where we are not trying to match a token
        vm.assume(repoToken == address(0));
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
            uint256 cumulativeWeightedTimeToMaturityCompletedAuctions,
            uint256 cumulativeOfferAmountCompletedAuctions,
            bool foundCompletedAuctions
        ) = getGroupedOfferTimeAndAmount(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision
        );

        assert(cumulativeWeightedTimeToMaturity == cumulativeWeightedTimeToMaturityCompletedAuctions);
        assert(cumulativeOfferAmount == cumulativeOfferAmountCompletedAuctions);
        assert(found == foundCompletedAuctions);

    }

    function _assumeRedemptionValueAndBalancePositive() internal {
        bytes32 current = _termAuctionList.head;

        while (current != TermAuctionList.NULL_NODE) {
            address repoToken = _termAuctionList.offers[current].repoToken;
            uint256 redemptionValue = ITermRepoToken(repoToken).redemptionValue();
            uint256 repoTokenBalance = ITermRepoToken(repoToken).balanceOf(address(this));
            vm.assume(0 < redemptionValue);
            vm.assume(0 < repoTokenBalance);

            current = _termAuctionList.nodes[current].next;
        }
    }

    function testGetCumulativeOfferData(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

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

        (
            uint256 cumulativeWeightedTimeToMaturityIncompletedAuctions,
            uint256 cumulativeOfferAmountIncompletedAuctions
        ) = filterCompletedAuctionsGetCumulativeOfferData();

        filterDiscountRateSet();
        filterRepeatedAuctions();

        (
            uint256 cumulativeWeightedTimeToMaturityCompletedAuctions,
            uint256 cumulativeOfferAmountCompletedAuctions
        ) = _getCumulativeOfferDataCompletedAuctions(discountRateAdapter, purchaseTokenPrecision);

        assert(cumulativeWeightedTimeToMaturity == cumulativeWeightedTimeToMaturityIncompletedAuctions + cumulativeWeightedTimeToMaturityCompletedAuctions);
        assert(cumulativeOfferAmount == cumulativeOfferAmountIncompletedAuctions + cumulativeOfferAmountCompletedAuctions);
    }

    function filterCompletedAuctionsGetTotalValue() internal returns (uint256 totalValue) {
        bytes32 current = _termAuctionList.head;
        bytes32 prev = current;

        while (current != TermAuctionList.NULL_NODE) {
            bytes32 next = _termAuctionList.nodes[current].next;

            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 offerAmount = TermAuctionOfferLocker(address(offer.offerLocker)).lockedOfferAmount(current);
            if (!offer.termAuction.auctionCompleted()) {
                totalValue += offerAmount;

                // Update the list to remove the current node
                delete _termAuctionList.nodes[current];
                delete _termAuctionList.offers[current];
                if (current == _termAuctionList.head) {
                    _termAuctionList.head = next;
                }
                else {
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

        address previous = address(0);

        while (current != TermAuctionList.NULL_NODE) {
            PendingOffer storage offer = _termAuctionList.offers[current];
            uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils.getNormalizedRepoTokenAmount(
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

    function testGetPresentTotalValue(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        // Consider only the case where we are not trying to match a token
        vm.assume(repoTokenToMatch == address(0));
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _termAuctionList.getPresentValue(
            _repoTokenList,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        uint256 totalValueNonCompletedAuctions = filterCompletedAuctionsGetTotalValue();

        filterDiscountRateSet();
        filterRepeatedAuctions();

        uint256 totalValueCompletedAuctions = _getTotalValueCompletedAuctions(ITermDiscountRateAdapter(address(discountRateAdapter)), purchaseTokenPrecision);

        assert(totalPresentValue == totalValueNonCompletedAuctions + totalValueCompletedAuctions);
    }
}
