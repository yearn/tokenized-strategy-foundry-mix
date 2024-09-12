// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {ITermController, AuctionMetadata} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract TermDiscountRateAdapter is ITermDiscountRateAdapter, AccessControl {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    ITermController public immutable TERM_CONTROLLER;
    mapping(address => mapping (bytes32 => bool)) public rateInvalid;
    mapping(address => uint256) public repoRedemptionHaircut;

    constructor(address termController_, address oracleWallet_) {
        TERM_CONTROLLER = ITermController(termController_);
        _grantRole(ORACLE_ROLE, oracleWallet_);        
    }

    /**
     * @notice Retrieves the discount rate for a given repo token
     * @param repoToken The address of the repo token
     * @return The discount rate for the specified repo token
     * @dev This function fetches the auction results for the repo token's term repo ID
     * and returns the clearing rate of the most recent auction
     */
    function getDiscountRate(address repoToken) public view virtual returns (uint256) {
        if (repoToken == address(0)) return 0;
        (AuctionMetadata[] memory auctionMetadata, ) = TERM_CONTROLLER.getTermAuctionResults(ITermRepoToken(repoToken).termRepoId());

        uint256 len = auctionMetadata.length;
        require(len > 0, "No auctions found");

        // If there is a re-opening auction, e.g. 2 or more results for the same token
        if (len > 1) {
            uint256 latestAuctionTime = auctionMetadata[len - 1].auctionClearingBlockTimestamp;
            if ((block.timestamp - latestAuctionTime) < 30 minutes) {
                for (int256 i = int256(len) - 2; i >= 0; i--) {
                    if (!rateInvalid[repoToken][auctionMetadata[uint256(i)].termAuctionId]) {
                        return auctionMetadata[uint256(i)].auctionClearingRate;
                    }
                }
            } else {
                for (int256 i = int256(len) - 1; i >= 0; i--) {
                    if (!rateInvalid[repoToken][auctionMetadata[uint256(i)].termAuctionId]) {
                        return auctionMetadata[uint256(i)].auctionClearingRate;
                    }
                }
            }
            revert("No valid auction rate found");
        }

        // If there is only 1 result (not a re-opening) then always return result
        return auctionMetadata[0].auctionClearingRate;
    }

    /**
    * @notice Sets the invalidity of the result of a specific auction for a given repo token
    * @dev This function is used to mark auction results as invalid or not, typically in cases of suspected manipulation
    * @param repoToken The address of the repo token associated with the auction
    * @param termAuctionId The unique identifier of the term auction to be invalidated
    * @param isInvalid The status of the rate invalidation
    * @custom:access Restricted to accounts with the ORACLE_ROLE
    */
    function setAuctionRateValidator(
        address repoToken, 
        bytes32 termAuctionId, 
        bool isInvalid
    ) external onlyRole(ORACLE_ROLE) {
        // Fetch the auction metadata for the given repo token
        (AuctionMetadata[] memory auctionMetadata, ) = TERM_CONTROLLER.getTermAuctionResults(ITermRepoToken(repoToken).termRepoId());

        // Check if the termAuctionId exists in the metadata
        bool auctionExists = _validateAuctionExistence(auctionMetadata, termAuctionId);

        // Revert if the auction doesn't exist
        require(auctionExists, "Auction ID not found in metadata");

        // Update the rate invalidation status
        rateInvalid[repoToken][termAuctionId] = isInvalid;
    }

    /**
     * @notice Set the repo redemption haircut
     * @param repoToken The address of the repo token
     * @param haircut The repo redemption haircut in 18 decimals
     */
    function setRepoRedemptionHaircut(address repoToken, uint256 haircut) external onlyRole(ORACLE_ROLE) {
        repoRedemptionHaircut[repoToken] = haircut;
    }

    function _validateAuctionExistence(AuctionMetadata[] memory auctionMetadata, bytes32 termAuctionId) private view returns(bool auctionExists) {
        // Check if the termAuctionId exists in the metadata
        bool auctionExists;
        for (uint256 i = 0; i < auctionMetadata.length; i++) {
            if (auctionMetadata[i].termAuctionId == termAuctionId) {
                auctionExists = true;
                break;
            }
        }
    }
}
