pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";
import "src/test/kontrol/ListTestUtils.t.sol";

contract RepoTokenListInvariantsTest is RepoTokenListTest {
    using RepoTokenList for RepoTokenListData;

    function setUp() public {
        // Make storage of this contract completely symbolic
        kevm.symbolicStorage(address(this));

        // Initialize RepoTokenList of arbitrary size
        _initializeRepoTokenList();
    }

    /**
     * Count the number of nodes in the list.
     *
     * Note that this function guarantees the following postconditions:
     * - The head of the list is NULL_NODE iff the count is 0.
     * - If the count is N, the Nth node in the list is followed by NULL_NODE.
     */
    function _countNodesInList() internal returns (uint256) {
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
    function _repoTokenInList(address repoToken) internal returns (bool) {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            if (current == repoToken) {
                return true;
            }

            current = _repoTokenList.nodes[current].next;
        }

        return false;
    }

    function _repoTokensListToArray(uint256 length) internal view returns (address[] memory repoTokens) {
        address current = _repoTokenList.head;
        uint256 i;
        repoTokens = new address[](length);

        while (current != RepoTokenList.NULL_NODE) {
            repoTokens[i++] = current;
            current = _repoTokenList.nodes[current].next;
        }
    }

    function _establishInsertListPreservation(address insertedRepoToken, address[] memory repoTokens, uint256 repoTokensCount) internal view {
        address current = _repoTokenList.head;
        uint256 i = 0;

        if(insertedRepoToken != address(0)) {

            while (current != RepoTokenList.NULL_NODE && i < repoTokensCount) {
                if(current != repoTokens[i]) {
                    assert (current == insertedRepoToken);
                    current = _repoTokenList.nodes[current].next;
                    break;
                }
                i++;
                current = _repoTokenList.nodes[current].next;
            }

            if (current != RepoTokenList.NULL_NODE && i == repoTokensCount) {
                assert (current == insertedRepoToken);
            }
        }

        while (current != RepoTokenList.NULL_NODE && i < repoTokensCount) {
            assert(current == repoTokens[i++]);
            current = _repoTokenList.nodes[current].next;
        }
    }

    function _establishRemoveListPreservation(address[] memory repoTokens, uint256 repoTokensCount) internal view {
        address current = _repoTokenList.head;
        uint256 i = 0;

        while (current != RepoTokenList.NULL_NODE && i < repoTokensCount) {
            if(current == repoTokens[i++]) {
                current = _repoTokenList.nodes[current].next;
            }
        }

        assert(current == RepoTokenList.NULL_NODE);
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
    function testInsertSortedDuplicateToken(
        address repoToken
    ) external {
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
     * Configure the model of the RepoServicer for every token in the list to
     * follow the assumption that redeemTermRepoTokens will not revert.
     */
    function _guaranteeRedeemAlwaysSucceeds() internal {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            (, , address repoServicer,) = ITermRepoToken(current).config();
            TermRepoServicer(repoServicer).guaranteeRedeemAlwaysSucceeds();

            current = _repoTokenList.nodes[current].next;
        }
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
}
