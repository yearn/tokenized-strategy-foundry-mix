// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermController, TermAuctionResults} from "../../interfaces/term/ITermController.sol";

contract MockTermController is ITermController {
    function isTermDeployed(address contractAddress) external view returns (bool) {
        return true;
    }

    function getTermAuctionResults(bytes32 termRepoId) external view returns (TermAuctionResults memory) {

    }
}