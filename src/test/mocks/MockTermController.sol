// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermController, AuctionMetadata, TermAuctionResults} from "../../interfaces/term/ITermController.sol";

contract MockTermController is ITermController {
    mapping(bytes32 => TermAuctionResults) internal auctionResults;

    function isTermDeployed(address contractAddress) external view returns (bool) {
        return true;
    }

    function setOracleRate(bytes32 termRepoId, uint256 oracleRate) external {
        AuctionMetadata memory metadata;

        metadata.auctionClearingRate = oracleRate;

        delete auctionResults[termRepoId];
        auctionResults[termRepoId].auctionMetadata.push(metadata);
        auctionResults[termRepoId].numOfAuctions = 1;
    }

    function getTermAuctionResults(bytes32 termRepoId) external view returns (TermAuctionResults memory) {
        return auctionResults[termRepoId];
    }
}