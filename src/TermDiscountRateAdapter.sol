// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {ITermController, AuctionMetadata} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";

contract TermDiscountRateAdapter is ITermDiscountRateAdapter {
    ITermController public immutable TERM_CONTROLLER;

    constructor(address termController_) {
        TERM_CONTROLLER = ITermController(termController_);
    }

    function getDiscountRate(address repoToken) external view returns (uint256) {
        (AuctionMetadata[] memory auctionMetadata, ) = TERM_CONTROLLER.getTermAuctionResults(ITermRepoToken(repoToken).termRepoId());

        uint256 len = auctionMetadata.length;
        require(len > 0);

        return auctionMetadata[len - 1].auctionClearingRate;
    }
}
