pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import "src/RepoTokenList.sol";

import {MockTermRepoToken} from "src/test/mocks/MockTermRepoToken.sol";
import {MockUSDC} from "src/test/mocks/MockUSDC.sol";

/**
 * Unit tests testing counterexamples for list invariants and other properties
 * found during formal verification. These tests would fail before the issues
 * were fixed, but should be passing after.
 */
contract CounterexamplesTest is Test {
    using RepoTokenList for RepoTokenListData;

    RepoTokenListData _listData;

    /**
     * Scenario: RepoTokenList is repoToken1 -> repoToken2 -> NULL_NODE, where
     * both tokens have the same maturity. We try to insert repoToken2 again.
     *
     * Before: repoToken2 was being inserted before the first token found with the
     * same maturity, making the list repoToken2 -> repoToken1 -> repoToken2 ->
     * repoToken1 -> ... and creating a cycle.
     *
     * After: A token is inserted only after all other tokens with the same
     * maturity. Therefore, the function continues past repoToken1 and sees that
     * repoToken2 is already in the list, avoiding inserting it again.
     */
    function testInsertSortedNoCycleCounterexample() external {
        MockUSDC mockUSDC = new MockUSDC();
        ERC20Mock mockCollateral = new ERC20Mock();

        // Deploy two repo tokens with the same maturity date
        MockTermRepoToken repoToken1 = new MockTermRepoToken(
            bytes32("test repo token 1"),
            address(mockUSDC),
            address(mockCollateral),
            1e18,
            block.timestamp + 1 weeks
        );
        MockTermRepoToken repoToken2 = new MockTermRepoToken(
            bytes32("test repo token 2"),
            address(mockUSDC),
            address(mockCollateral),
            1e18,
            block.timestamp + 1 weeks
        );

        // Initialize list to repoToken1 -> repoToken2 -> NULL_NODE
        _listData.head = address(repoToken1);
        _listData.nodes[address(repoToken1)].next = address(repoToken2);
        _listData.nodes[address(repoToken2)].next = RepoTokenList.NULL_NODE;

        // Try to insert repoToken2 again, shouldn't change the list
        _listData.insertSorted(address(repoToken2));

        address previous = RepoTokenList.NULL_NODE;
        address current = _listData.head;

        // Check that no next pointers point to the previous node
        while (current != RepoTokenList.NULL_NODE) {
            address next = _listData.nodes[current].next;

            assert(next != previous);

            previous = current;
            current = next;
        }
    }
}
