// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ITermAuctionOfferLocker {
    /// @dev TermAuctionOfferSubmission represents an offer submission to offeror an amount of money for a specific interest rate
    struct TermAuctionOfferSubmission {
        /// @dev For an existing offer this is the unique onchain identifier for this offer. For a new offer this is a randomized input that will be used to generate the unique onchain identifier.
        bytes32 id;
        /// @dev The address of the offeror
        address offeror;
        /// @dev Hash of the offered price as a percentage of the initial loaned amount vs amount returned at maturity. This stores 9 decimal places
        bytes32 offerPriceHash;
        /// @dev The maximum amount of purchase tokens that can be lent
        uint256 amount;
        /// @dev The address of the ERC20 purchase token
        address purchaseToken;
    }
    function termRepoId() external view returns (bytes32);

    function termAuctionId() external view returns (bytes32);

    function auctionStartTime() external view returns (uint256);

    function auctionEndTime() external view returns (uint256);

    function revealTime() external view returns (uint256);

    function purchaseToken() external view returns (address);

    function termRepoServicer() external view returns (address);

    /// @param offerSubmissions An array of offer submissions
    /// @return A bytes32 array of unique on chain offer ids.
    function lockOffers(
        TermAuctionOfferSubmission[] calldata offerSubmissions
    ) external returns (bytes32[] memory);
}
