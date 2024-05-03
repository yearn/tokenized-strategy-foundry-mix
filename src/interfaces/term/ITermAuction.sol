// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ITermAuction {
    function termAuctionOfferLocker() external view returns (address);
    
    function termRepoId() external view returns (bytes32);

    function auctionEndTime() external view returns (uint256);

    function auctionCompleted() external view returns (bool);

    function auctionCancelledForWithdrawal() external view returns (bool);
}