// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ITermRepoServicer {
    function redeemTermRepoTokens(
        address redeemer,
        uint256 amountToRedeem
    ) external;

    function termRepoToken() external view returns (address);

    function termRepoLocker() external view returns (address);

    function purchaseToken() external view returns (address);
}
