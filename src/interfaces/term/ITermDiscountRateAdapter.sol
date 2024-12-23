// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ITermController} from "./ITermController.sol";
interface ITermDiscountRateAdapter {
    function currTermController() external view returns (ITermController);
    function repoRedemptionHaircut(address) external view returns (uint256);
    function getDiscountRate(address repoToken) external view returns (uint256);
    function getDiscountRate(
        address termController,
        address repoToken
    ) external view returns (uint256);
}
