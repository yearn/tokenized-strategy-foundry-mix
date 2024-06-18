// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

struct AuctionMetadata {
    bytes32 termAuctionId;
    uint256 auctionClearingRate;
    uint256 auctionClearingBlockTimestamp;
}

interface ITermController {
    function isTermDeployed(address contractAddress) external view returns (bool);

    function getTermAuctionResults(bytes32 termRepoId) external view returns (AuctionMetadata[] memory auctionMetadata, uint8 numOfAuctions);
}
