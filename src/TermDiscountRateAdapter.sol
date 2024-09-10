// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {ITermController, AuctionMetadata} from "./interfaces/term/ITermController.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import "@openzeppelin/contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/**
 * @title TermDiscountRateAdapter
 * @notice Adapter contract to retrieve discount rates for Term repo tokens
 * @dev This contract implements the ITermDiscountRateAdapter interface and interacts with the Term Controller
 */
contract TermDiscountRateAdapter is ITermDiscountRateAdapter, AccessControlUpgradeable {

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    /// @notice The Term Controller contract
    ITermController public immutable TERM_CONTROLLER;
    mapping(address => uint256) public repoRedemptionHaircut;

    /**
     * @notice Constructor to initialize the TermDiscountRateAdapter
     * @param termController_ The address of the Term Controller contract
     * @param oracleWallet_ The address of the oracle wallet
     */
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
    function getDiscountRate(address repoToken) external view returns (uint256) {
        (AuctionMetadata[] memory auctionMetadata, ) = TERM_CONTROLLER.getTermAuctionResults(ITermRepoToken(repoToken).termRepoId());

        uint256 len = auctionMetadata.length;
        require(len > 0);

        return auctionMetadata[len - 1].auctionClearingRate;
    }

    /**
     * @notice Set the repo redemption haircut
     * @param repoToken The address of the repo token
     * @param haircut The repo redemption haircut in 18 decimals
     */
    function setRepoRedemptionHaircut(address repoToken, uint256 haircut) external onlyRole(ORACLE_ROLE) {
        repoRedemptionHaircut[repoToken] = haircut;
    }
}