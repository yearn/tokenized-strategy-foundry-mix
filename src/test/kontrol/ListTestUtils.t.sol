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


contract RepoTokenListTest is KontrolTest {
    using RepoTokenList for RepoTokenListData;

    RepoTokenListData _repoTokenList;

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
    function _establishNoDuplicateTokens(Mode mode) internal {
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
     * Weaker version of the above invariant that allows matured tokens to have
     * a balance of 0.
     *
     * Note: This is equivalent to the above invariant if the NoMaturedTokens
     * invariant also holds.
     */
    function _establishPositiveBalanceForNonMaturedTokens(Mode mode) internal {
        address current = _repoTokenList.head;

        while (current != RepoTokenList.NULL_NODE) {
            uint256 currentMaturity = _getRepoTokenMaturity(current);
            uint256 repoTokenBalance = _getRepoTokenBalance(current);

            if (block.timestamp < currentMaturity) {
                _establish(mode, 0 < repoTokenBalance);
            }

            current = _repoTokenList.nodes[current].next;
        }
    }
}

contract TermAuctionListTest is KontrolTest {
    using TermAuctionList for TermAuctionListData;
    using RepoTokenList for RepoTokenListData;

    TermAuctionListData _termAuctionList;
    address _referenceAuction;

    uint256 private auctionListSlot;

    function auctionListOfferSlot(bytes32 offerId) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint256(offerId), uint256(auctionListSlot + 2))));
    }

    function setReferenceAuction() internal {
        // We will copy the code of this deployed auction contract
        // into all auctions in the list
        uint256 referenceAuctionSlot;
        assembly {
            referenceAuctionSlot := _referenceAuction.slot
            sstore(auctionListSlot.slot, _termAuctionList.slot)
        }
        _storeUInt256(address(this), referenceAuctionSlot, uint256(uint160(address(new TermAuction()))));
    }

    /**
     * Set pending offer using slot manipulation directly
     */
    function setPendingOffer(bytes32 offerId, address repoToken, uint256 offerAmount, address auction, address offerLocker) internal {
        uint256 offerSlot = auctionListOfferSlot(offerId);
        _storeUInt256(address(this), offerSlot, uint256(uint160(repoToken)));
        _storeUInt256(address(this), offerSlot + 1, offerAmount);
        _storeUInt256(address(this), offerSlot + 2, uint256(uint160(auction)));
        _storeUInt256(address(this), offerSlot + 3, uint256(uint160(offerLocker)));
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
     * Etch the code at a given address to a given address in an external call,
     * reducing memory consumption in the caller function
     */
    function etch(address dest, address src) public {
      vm.etch(dest, src.code);
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
            if(count == 0 || kevm.freshBool() != 0) {
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
            setPendingOffer(current, address(repoToken), freshUInt256(), auction, address(offerLocker));

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

}

