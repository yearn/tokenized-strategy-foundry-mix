// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermAuction} from "../../interfaces/term/ITermAuction.sol";
import {ITermRepoToken} from "../../interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "../../interfaces/term/ITermRepoServicer.sol";
import {MockTermAuctionOfferLocker} from "./MockTermAuctionOfferLocker.sol";

contract MockTermAuction is ITermAuction {
    
    address public termAuctionOfferLocker;
    bytes32 public termRepoId;
    uint256 public auctionEndTime;
    bool public auctionCompleted;
    bool public auctionCancelledForWithdrawal;
    
    constructor(ITermRepoToken _repoToken) {
        termRepoId = _repoToken.termRepoId();
        (
            uint256 redemptionTimestamp,
            address purchaseToken,
            address termRepoServicer,
            address termRepoCollateralManager
        ) = _repoToken.config();
        termAuctionOfferLocker = address(new MockTermAuctionOfferLocker(
            ITermAuction(address(this)), 
            ITermRepoServicer(termRepoServicer).termRepoLocker(), 
            termRepoServicer,
            purchaseToken
        ));
    }

    function startAuction(uint256 duration) external {
        auctionEndTime = block.timestamp + duration;
    }

    function clearAuction() external {
        
    }
}
