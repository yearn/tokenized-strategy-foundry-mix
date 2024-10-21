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
        _initializeRepoTokenList();
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

    function testGetCumulativeData(
        address repoToken,
        uint256 newOfferAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        // Assume relevant invariants
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

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

        // TODO: Add checks that calculation is correct
    }

    function testGetPresentValue(
        uint256 purchaseTokenPrecision,
        address repoTokenToMatch
    ) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        // Assume relevant invariants
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Consider only the case where we are not trying to match a token
        vm.assume(repoTokenToMatch == address(0));
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _termAuctionList.getPresentValue(
            _repoTokenList,
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision,
            repoTokenToMatch
        );

        // TODO: Add checks that calculation is correct
    }
}
