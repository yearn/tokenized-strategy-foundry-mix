pragma solidity 0.8.23;

import "src/test/kontrol/RepoTokenListInvariants.t.sol";
import "src/test/kontrol/TermDiscountRateAdapter.sol";

contract RepoTokenGetTest is RepoTokenListInvariantsTest {
    using RepoTokenList for RepoTokenListData;

    function _initializeRepoTokenListEmpty() internal {
        _repoTokenList.head = RepoTokenList.NULL_NODE;
    }

    function testGetCumulativeDataEmpty(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        _initializeRepoTokenListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount,
            bool found
        ) = _repoTokenList.getCumulativeRepoTokenData(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            repoToken,
            repoTokenAmount,
            purchaseTokenPrecision
        );

        assert(cumulativeWeightedTimeToMaturity == 0);
        assert(cumulativeRepoTokenAmount == 0);
        assert(found == false);
    }

    function testGetPresentValueEmpty(
        uint256 purchaseTokenPrecision
    ) external {
        _initializeRepoTokenListEmpty();

        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();

        uint256 totalPresentValue = _repoTokenList.getPresentValue(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision
        );

        assert(totalPresentValue == 0);
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
    ) internal view returns (
        uint256 cumulativeWeightedTimeToMaturity,
        uint256 cumulativeRepoTokenAmount
    ) {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            (uint256 currentMaturity, , ,) = ITermRepoToken(current).config();
            assert(currentMaturity > block.timestamp);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));
            uint256 repoRedemptionHaircut = discountRateAdapter.repoRedemptionHaircut(current);
            uint256 timeToMaturity = currentMaturity - block.timestamp;

            uint256 repoTokenAmountInBaseAssetPrecision =
                RepoTokenUtils.getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    repoRedemptionHaircut
                );

            uint256 weightedTimeToMaturity =
                timeToMaturity * repoTokenAmountInBaseAssetPrecision;

            cumulativeWeightedTimeToMaturity += weightedTimeToMaturity;
            cumulativeRepoTokenAmount += repoTokenAmountInBaseAssetPrecision;

            current = _repoTokenList.nodes[current].next;
        }
    }

    function testGetCumulativeData(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize RepoTokenList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        // Assume relevant invariants
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        // Consider only the case where we are not trying to match a token
        vm.assume(repoToken == address(0));
        vm.assume(purchaseTokenPrecision <= 18);

        (
            uint256 cumulativeWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount,
            bool found
        ) = _repoTokenList.getCumulativeRepoTokenData(
            discountRateAdapter,
            repoToken,
            repoTokenAmount,
            purchaseTokenPrecision
        );

        assert(!found);

        // Simplified calculation in the case no tokens have matured
        (
         uint256 cumulativeWeightedTimeToMaturityNotMatured,
         uint256 cumulativeRepoTokenAmountNotMatured
        ) = _cumulativeRepoTokenDataNotMatured(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        assert(
            cumulativeWeightedTimeToMaturity ==
            cumulativeWeightedTimeToMaturityNotMatured
        );

        assert(
            cumulativeRepoTokenAmount ==
            cumulativeRepoTokenAmountNotMatured
        );
    }

    // Calculates the total present value assuming that no tokens have matured
    function _totalPresentValueNotMatured(
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 purchaseTokenPrecision
    ) internal view returns (uint256) {
        address current = _repoTokenList.head;
        uint256 totalPresentValue = 0;

        while (current != RepoTokenList.NULL_NODE) {
            (uint256 currentMaturity, , ,) = ITermRepoToken(current).config();
            assert(currentMaturity > block.timestamp);
            uint256 repoTokenBalance = ITermRepoToken(current).balanceOf(address(this));
            uint256 repoRedemptionHaircut = discountRateAdapter.repoRedemptionHaircut(current);
            uint256 discountRate = discountRateAdapter.getDiscountRate(current);
            uint256 timeToMaturity = currentMaturity - block.timestamp;

            uint256 repoTokenAmountInBaseAssetPrecision =
                RepoTokenUtils.getNormalizedRepoTokenAmount(
                    current,
                    repoTokenBalance,
                    purchaseTokenPrecision,
                    repoRedemptionHaircut
                );

            uint256 timeLeftToMaturityDayFraction =
                (timeToMaturity * purchaseTokenPrecision) / 360 days;

            uint256 presentValue =
                (repoTokenAmountInBaseAssetPrecision * purchaseTokenPrecision) / 
                (purchaseTokenPrecision + (discountRate * timeLeftToMaturityDayFraction / 1e18));

            totalPresentValue += presentValue;

            current = _repoTokenList.nodes[current].next;
        }

        return totalPresentValue;
    }

    function testGetPresentValue(
        uint256 purchaseTokenPrecision
    ) external {
        // Initialize RepoTokenList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        // Assume relevant invariants
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter =
            new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        vm.assume(0 < purchaseTokenPrecision);
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _repoTokenList.getPresentValue(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        // Simplified calculation in the case no tokens have matured
        uint256 totalPresentValueNotMatured = _totalPresentValueNotMatured(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        assert(totalPresentValue == totalPresentValueNotMatured);
    }
}
