pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/RepoTokenList.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/RepoToken.sol";

enum Mode {
    Assume,
    Assert
}

contract RepoTokenListInvariantsTest is Test, KontrolCheats {
    using RepoTokenList for RepoTokenListData;

    RepoTokenListData _repoTokenList;

    /**
     * Either assume or assert a condition, depending on the specified mode.
     */
    function _establish(Mode mode, bool condition) internal {
        if (mode == Mode.Assume) {
            vm.assume(condition);
        } else {
            assertTrue(condition);
        }
    }

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
    function _getRepoTokenMaturity(address repoToken) internal returns (uint256 redemptionTimestamp) {
        (redemptionTimestamp, , ,) = ITermRepoToken(repoToken).config();
    }

    /**
     * Return the this contract's balance in the given RepoToken.
     */
    function _getRepoTokenBalance(address repoToken) internal returns (uint256) {
        return ITermRepoToken(repoToken).balanceOf(address(this));
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
     * Assume or assert that the tokens in the list are sorted by maturity.
     */
    function _establishSortedByMaturity(Mode mode) internal {
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
    function _establishNoDuplicates(Mode mode) internal {
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
    function _establishNoMaturedTokens(Mode mode) internal {
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
    function _establishPositiveBalance(Mode mode) internal {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            uint256 repoTokenBalance = _getRepoTokenBalance(current);

            _establish(mode, 0 < repoTokenBalance);

            current = _repoTokenList.nodes[current].next;
        }
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

    /**
     * Test that insertSorted preserves the list invariants when a new RepoToken
     * is added (that was not present in the list before).
     */
    function testInsertSortedNewToken() external {
        // Initialize RepoTokenList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        // Assume that the invariants are satisfied before the function is called
        _establishSortedByMaturity(Mode.Assume);
        _establishNoDuplicates(Mode.Assume);
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countNodesInList();

        // Generate a new RepoToken with symbolic storage
        address repoToken = _newRepoToken();
        uint256 maturity = _getRepoTokenMaturity(repoToken);
        uint256 balance = _getRepoTokenBalance(repoToken);
        vm.assume(block.timestamp < maturity);
        vm.assume(0 < balance);

        // Call the function being tested
        _repoTokenList.insertSorted(repoToken);


        // Assert that the size of the list increased by 1
        assertEq(_countNodesInList(), count + 1);

        // Assert that the new RepoToken is in the list
        assertTrue(_repoTokenInList(repoToken));

        // Assert that the invariants are preserved
        _establishSortedByMaturity(Mode.Assert);
        _establishNoDuplicates(Mode.Assert);
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
        // Initialize RepoTokenList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        // Assume that the invariants are satisfied before the function is called
        _establishSortedByMaturity(Mode.Assume);
        _establishNoDuplicates(Mode.Assume);
        _establishNoMaturedTokens(Mode.Assume);
        _establishPositiveBalance(Mode.Assume);

        // Save the number of tokens in the list before the function is called
        uint256 count = _countNodesInList();

        // Assume that the RepoToken is already in the list
        vm.assume(_repoTokenInList(repoToken));

        // Call the function being tested
        _repoTokenList.insertSorted(repoToken);

        // Assert that the size of the list didn't change
        assertEq(_countNodesInList(), count);

        // Assert that the RepoToken is still in the list
        assertTrue(_repoTokenInList(repoToken));

        // Assert that the invariants are preserved
        _establishSortedByMaturity(Mode.Assert);
        _establishNoDuplicates(Mode.Assert);
        _establishNoMaturedTokens(Mode.Assert);
        _establishPositiveBalance(Mode.Assume);
    }

    /**
     * Test that removeAndRedeemMaturedTokens preserves the list invariants.
     */
    function testRemoveAndRedeemMaturedTokens() external {
        // Initialize RepoTokenList of arbitrary size
        kevm.symbolicStorage(address(this));
        _initializeRepoTokenList();

        // Save the number of tokens in the list before the function is called
        uint256 count = _countNodesInList();

        // Assume that the invariants are satisfied before the function is called
        _establishSortedByMaturity(Mode.Assume);
        _establishNoDuplicates(Mode.Assume);

        // TODO: Can we assume for this test that token redemption always
        // succeeds? Otherwise some of the invariants might not be preserved.

        // Call the function being tested
        _repoTokenList.removeAndRedeemMaturedTokens();

        // Assert that the size of the list is less than or equal to before
        assertLe(_countNodesInList(), count);

        // Assert that the invariants are preserved
        _establishSortedByMaturity(Mode.Assert);
        _establishNoDuplicates(Mode.Assert);

        // Now the following invariants should hold as well
        _establishNoMaturedTokens(Mode.Assert);
        _establishPositiveBalance(Mode.Assume);
    }
}
