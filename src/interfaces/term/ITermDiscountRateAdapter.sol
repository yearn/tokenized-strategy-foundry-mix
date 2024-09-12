// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermController} from "./ITermController.sol";
interface ITermDiscountRateAdapter {
    function TERM_CONTROLLER() external view returns (ITermController);
    function repoRedemptionHaircut(address) external view returns (uint256);
    function getDiscountRate(address repoToken) external view returns (uint256);
}
