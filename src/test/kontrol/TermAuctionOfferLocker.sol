pragma solidity 0.8.23;

import "src/interfaces/term/ITermAuctionOfferLocker.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/KontrolTest.sol";

contract TermAuctionOfferLocker is ITermAuctionOfferLocker, KontrolTest {
    mapping(bytes32 => TermAuctionOffer) _lockedOffers;
    address _termRepoServicer;
    bool _unlockAlwaysSucceeds;

    uint256 private constant lockedOffersSlot = 27;
    uint256 private constant repoServicerAndUnlockSlot = 28;

    function lockedOfferSlot(bytes32 offerId) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(uint256(offerId), uint256(lockedOffersSlot))));
    }

    function initializeSymbolic(address termRepoServicer) public {
        kevm.symbolicStorage(address(this));
        // Clear slot which holds two contract fields
        _storeUInt256(address(this), repoServicerAndUnlockSlot, 0);
        _termRepoServicer = termRepoServicer;
        _unlockAlwaysSucceeds = false;
    }

    function initializeSymbolicLockedOfferFor(bytes32 offerId) public {
        TermAuctionOffer storage offer = _lockedOffers[offerId];
        offer.amount = freshUInt256();
        vm.assume(offer.amount < ETH_UPPER_BOUND);

        uint256 _purchaseToken = uint160(kevm.freshAddress());
        uint256 _isRevealed = uint96(kevm.freshBool());
        bytes memory offerLastSlotAbi = abi.encodePacked(uint96(_isRevealed), uint160(_purchaseToken));
        bytes32 offerLastSlot;
        assembly {
            offerLastSlot := mload(add(offerLastSlotAbi, 0x20))
        }
        _storeBytes32(address(this), lockedOfferSlot(offerId) + 5, offerLastSlot);
    }

    function guaranteeUnlockAlwaysSucceeds() external {
        _unlockAlwaysSucceeds = true;
    }

    function termRepoId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function termAuctionId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function auctionStartTime() external view returns (uint256) {
        return freshUInt256();
    }

    function auctionEndTime() external view returns (uint256) {
        return freshUInt256();
    }

    function revealTime() external view returns (uint256) {
        return freshUInt256();
    }

    function purchaseToken() external view returns (address) {
        return kevm.freshAddress();
    }

    function termRepoServicer() external view returns (address) {
        return _termRepoServicer;
    }

    function lockedOffer(bytes32 id) external view returns (TermAuctionOffer memory) {
        return _lockedOffers[id];
    }

    function lockOffers(
        TermAuctionOfferSubmission[] calldata offerSubmissions
    ) external returns (bytes32[] memory) {
        kevm.symbolicStorage(address(this));

        uint256 length = freshUInt256();
        bytes32[] memory offers = new bytes32[](length);

        for (uint256 i = 0; i < length; ++i) {
            offers[i] = bytes32(freshUInt256());
        }

        return offers;
    }

    function unlockOffers(bytes32[] calldata offerIds) external {
        // Function might revert in some cases
        if (!_unlockAlwaysSucceeds) {
            require(kevm.freshBool() != 0);
        }

        kevm.symbolicStorage(_termRepoServicer);
        kevm.symbolicStorage(address(this));
    }
}
