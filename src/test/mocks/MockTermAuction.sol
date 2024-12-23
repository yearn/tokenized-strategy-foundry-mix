// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermAuction} from "../../interfaces/term/ITermAuction.sol";
import {ITermAuctionOfferLocker} from "../../interfaces/term/ITermAuctionOfferLocker.sol";
import {ITermRepoToken} from "../../interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "../../interfaces/term/ITermRepoServicer.sol";
import {MockTermAuctionOfferLocker} from "./MockTermAuctionOfferLocker.sol";
import {MockTermRepoToken} from "./MockTermRepoToken.sol";

contract MockTermAuction is ITermAuction {
    address public termAuctionOfferLocker;
    bytes32 public termRepoId;
    uint256 public auctionEndTime;
    bool public auctionCompleted;
    bool public auctionCancelledForWithdrawal;
    ITermRepoToken internal repoToken;

    constructor(ITermRepoToken _repoToken) {
        termRepoId = _repoToken.termRepoId();
        repoToken = _repoToken;
        (
            uint256 redemptionTimestamp,
            address purchaseToken,
            address termRepoServicer,
            address termRepoCollateralManager
        ) = _repoToken.config();
        termAuctionOfferLocker = address(
            new MockTermAuctionOfferLocker(
                ITermAuction(address(this)),
                ITermRepoServicer(termRepoServicer).termRepoLocker(),
                termRepoServicer,
                purchaseToken
            )
        );
        auctionEndTime = block.timestamp + 1 weeks;
    }

    function auctionSuccess(
        bytes32[] calldata offerIds,
        uint256[] calldata fillAmounts,
        uint256[] calldata repoTokenAmounts
    ) external {
        auctionCompleted = true;
        auctionEndTime = block.timestamp;

        for (uint256 i; i < offerIds.length; i++) {
            MockTermAuctionOfferLocker(termAuctionOfferLocker).processOffer(
                MockTermRepoToken(address(repoToken)),
                offerIds[i],
                fillAmounts[i],
                repoTokenAmounts[i]
            );
        }
    }

    function auctionCancelForWithdrawal() external {
        auctionCancelledForWithdrawal = true;
    }

    function auctionCancel(bytes32[] calldata offerIds) external {
        uint256 i = 0;
        // Return revealed offer funds.
        for (i = 0; i < offerIds.length; ++i) {
            ITermAuctionOfferLocker.TermAuctionOffer
                memory offer = MockTermAuctionOfferLocker(
                    termAuctionOfferLocker
                ).lockedOffer(offerIds[i]);

            MockTermAuctionOfferLocker(termAuctionOfferLocker)
                .unlockOfferPartial(offer.id, offer.offeror, offer.amount);
        }
    }
}
