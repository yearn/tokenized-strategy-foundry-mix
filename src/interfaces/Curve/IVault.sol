// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ICurveLendVault {
    function asset() external view returns (address);
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function maxWithdraw(address) external view returns (uint256);
}