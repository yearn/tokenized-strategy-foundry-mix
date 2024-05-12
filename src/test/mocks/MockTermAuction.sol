// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermAuction} from "../../interfaces/term/ITermAuction.sol";

contract MockTermAuction is ITermAuction {
    
    address public termAuctionOfferLocker;
    bytes32 public termRepoId;
    uint256 public auctionEndTime;
    bool public auctionCompleted;
    bool public auctionCancelledForWithdrawal;
    
    constructor(bytes32 _termRepoId) {
        termRepoId = _termRepoId;
    }

    function setOfferLocker(address _termAuctionOfferLocker) external {
        termAuctionOfferLocker = _termAuctionOfferLocker;
    }

    function startAuction(uint256 duration) external {
        auctionEndTime = block.timestamp + duration;
    }

    function clearAuction() external {
        
    }
}
