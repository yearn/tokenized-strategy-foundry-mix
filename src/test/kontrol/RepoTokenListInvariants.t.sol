pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/RepoTokenListTest.t.sol";

contract RepoTokenListInvariantsTest is RepoTokenListTest {
    using RepoTokenList for RepoTokenListData;

    function setUp() public {
        // Make storage of this contract completely symbolic
        kevm.symbolicStorage(address(this));

        // Initialize RepoTokenList of arbitrary size
        _initializeRepoTokenList();
    }

    /**
     * Test that insertSorted preserves the list invariants when a new RepoToken
     * is added (that was not present in the list before).
     */
    function testInsertSortedNewToken() external {
        // Our initialization procedure guarantees this invariant,
        // so we assert instead of assuming
        _establishNoDuplicateTokens(Mode.Assert);

        // Assume that the invariants are satisfied before the function is called
        _establishSortedByMaturity(Mode.Assume);
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countNodesInList();

        address[] memory repoTokens = _repoTokensListToArray(count);

        // Generate a new RepoToken with symbolic storage
        address repoToken = _newRepoToken();
        uint256 maturity = _getRepoTokenMaturity(repoToken);
        uint256 balance = _getRepoTokenBalance(repoToken);
        vm.assume(block.timestamp < maturity);
        vm.assume(0 < balance);

        // Call the function being tested
        _repoTokenList.insertSorted(repoToken);

        // Assert that the size of the list increased by 1
        assert(_countNodesInList() == count + 1);

        // Assert that the new RepoToken is in the list
        //assert(_repoTokenInList(repoToken));

        _establishInsertListPreservation(repoToken, repoTokens, count);

        // Assert that the invariants are preserved
        _establishSortedByMaturity(Mode.Assert);
        _establishNoDuplicateTokens(Mode.Assert);
        _establishNoMaturedTokens(Mode.Assert);
        _establishPositiveBalance(Mode.Assert);
    }

    /**
     * Test that insertSorted preserves the list invariants when trying to
     * insert a RepoToken that is already in the list.
     */
    function testInsertSortedDuplicateToken(address repoToken) external {
        // Our initialization procedure guarantees this invariant,
        // so we assert instead of assuming
        _establishNoDuplicateTokens(Mode.Assert);

        // Assume that the invariants are satisfied before the function is called
        _establishSortedByMaturity(Mode.Assume);
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countNodesInList();

        address[] memory repoTokens = _repoTokensListToArray(count);

        // Assume that the RepoToken is already in the list
        vm.assume(_repoTokenInList(repoToken));

        // Call the function being tested
        _repoTokenList.insertSorted(repoToken);

        // Assert that the size of the list didn't change
        assert(_countNodesInList() == count);

        // Assert that the RepoToken is still in the list
        //assert(_repoTokenInList(repoToken));

        _establishInsertListPreservation(address(0), repoTokens, count);

        // Assert that the invariants are preserved
        _establishSortedByMaturity(Mode.Assert);
        _establishNoDuplicateTokens(Mode.Assert);
        _establishNoMaturedTokens(Mode.Assert);
        _establishPositiveBalance(Mode.Assert);
    }

    /**
     * Test that removeAndRedeemMaturedTokens preserves the list invariants.
     */
    function testRemoveAndRedeemMaturedTokens() external {
        // Save the number of tokens in the list before the function is called
        uint256 count = _countNodesInList();
        address[] memory repoTokens = _repoTokensListToArray(count);

        // Our initialization procedure guarantees this invariant,
        // so we assert instead of assuming
        _establishNoDuplicateTokens(Mode.Assert);

        // Assume that the invariants are satisfied before the function is called
        _establishSortedByMaturity(Mode.Assume);
        _establishPositiveBalanceForNonMaturedTokens(Mode.Assume);

        // Assume that the call to redeemTermRepoTokens will not revert
        _guaranteeRedeemAlwaysSucceeds();

        // Call the function being tested
        _repoTokenList.removeAndRedeemMaturedTokens();

        // Assert that the size of the list is less than or equal to before
        assert(_countNodesInList() <= count);

        _establishRemoveListPreservation(repoTokens, count);

        // Assert that the invariants are preserved
        _establishSortedByMaturity(Mode.Assert);
        _establishNoDuplicateTokens(Mode.Assert);

        // Now the following invariants should hold as well
        _establishNoMaturedTokens(Mode.Assert);
        _establishPositiveBalance(Mode.Assert);
    }

    function testGetCumulativeDataEmpty(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        _initializeRepoTokenListEmpty();

        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();

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

    function testGetPresentValueEmpty(uint256 purchaseTokenPrecision) external {
        _initializeRepoTokenListEmpty();

        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();

        uint256 totalPresentValue = _repoTokenList.getPresentValue(
            ITermDiscountRateAdapter(address(discountRateAdapter)),
            purchaseTokenPrecision
        );

        assert(totalPresentValue == 0);
    }

    function testGetCumulativeRepoTokenData(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 purchaseTokenPrecision
    ) external {
        // Assume relevant invariants
        _establishPositiveBalance(Mode.Assume);

        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
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

        // Removes matured tokens and returns their total value
        uint256 cumulativeRepoTokenAmountMatured = _filterMaturedTokensGetTotalValue(
                discountRateAdapter,
                purchaseTokenPrecision
            );

        // Simplified calculation for no matured tokens
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
                cumulativeRepoTokenAmountMatured +
                    cumulativeRepoTokenAmountNotMatured
        );
    }

    function testGetPresentTotalValue(uint256 purchaseTokenPrecision) external {
        // Initialize a DiscountRateAdapter with symbolic storage
        TermDiscountRateAdapter discountRateAdapter = new TermDiscountRateAdapter();
        _initializeDiscountRateAdapter(discountRateAdapter);

        vm.assume(0 < purchaseTokenPrecision);
        vm.assume(purchaseTokenPrecision <= 18);

        uint256 totalPresentValue = _repoTokenList.getPresentValue(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        // Removes matured tokens and returns their total value
        uint256 totalPresentValueMatured = _filterMaturedTokensGetTotalValue(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        uint256 totalPresentValueNotMatured = _totalPresentValueNotMatured(
            discountRateAdapter,
            purchaseTokenPrecision
        );

        assert(
            totalPresentValue ==
                totalPresentValueMatured + totalPresentValueNotMatured
        );
    }
}
